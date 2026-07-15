package app.opendisplay.android;

import android.media.MediaCodec;
import android.media.MediaCodecInfo;
import android.media.MediaCodecList;
import android.media.MediaFormat;
import android.os.Handler;
import android.os.HandlerThread;
import android.util.Log;
import android.view.Surface;

import java.io.IOException;
import java.util.ArrayList;
import java.util.List;

import app.opendisplay.android.protocol.AnnexB;
import app.opendisplay.android.protocol.SpsParser;

public final class H264SurfaceDecoder {
    private static final String LOG_TAG = "DisplayWeaveDecoder";
    private static final int MAX_RENDERED_TELEMETRY = 512;
    private static final int MAX_PENDING_INPUT_FRAMES = 3;
    private final Surface surface;
    private final DecoderLowLatencyMode lowLatencyMode;
    private volatile Listener listener;
    private MediaCodec codec;
    private int configuredWidth;
    private int configuredHeight;
    private long presentationUs;
    private VideoStreamConfig streamConfig = VideoStreamConfig.DEFAULT;
    private final DecoderCallbackState callbackState =
            new DecoderCallbackState(MAX_RENDERED_TELEMETRY);
    private final BoundedOrderedQueue<VideoFramePacket> pendingInputFrames =
            new BoundedOrderedQueue<>(MAX_PENDING_INPUT_FRAMES);
    private final ReferenceChainRecovery referenceChainRecovery =
            new ReferenceChainRecovery();
    private HandlerThread renderedCallbackThread;
    private long lastMissingParameterLogMs;
    private DecoderRuntimeInfo lastRuntimeInfo;

    public interface Listener {
        void onDecoderStatus(String status);
        void onDecoderReady(DecoderRuntimeInfo info);
        void onDecoderConfigurationFailed(DecoderRuntimeInfo info);
        void onDecoderNeedsKeyframe();
        void onDecoderCodecFailure(String codec, String message);
        void onDecoderFrameDropped(AndroidDropReason reason, VideoFrameTelemetry telemetry);
        void onDecoderFrameSubmitted();
        void onDecoderPendingQueueOverflow();
        void onDecoderRecoveryStarted();
        void onDecoderRecoveryCompleted(long durationMs);
        void onDecoderFrameDecoded();
        void onDecoderFrameRendered(VideoFrameTelemetry telemetry);
    }

    public H264SurfaceDecoder(Surface surface, Listener listener) {
        this(surface, listener, DecoderLowLatencyMode.AUTO);
    }

    public H264SurfaceDecoder(Surface surface, Listener listener,
                              DecoderLowLatencyMode lowLatencyMode) {
        this.surface = surface;
        this.listener = listener;
        this.lowLatencyMode = lowLatencyMode == null
                ? DecoderLowLatencyMode.AUTO : lowLatencyMode;
    }

    public synchronized boolean rebindIfConfigured(Listener nextListener) {
        listener = nextListener;
        if (codec == null || lastRuntimeInfo == null) {
            return false;
        }
        nextListener.onDecoderReady(lastRuntimeInfo);
        nextListener.onDecoderStatus("正在接收 " + configuredWidth + "×" + configuredHeight
                + " · " + streamConfig.codec + " · " + streamConfig.fps + "fps");
        return true;
    }

    public void applyStreamConfig(String codecName, int fps, int width, int height) {
        VideoStreamConfig next = VideoStreamConfig.from(codecName, fps, width, height, 0);
        boolean changed;
        synchronized (this) {
            changed = !streamConfig.codec.equals(next.codec) || streamConfig.fps != next.fps
                    || (configuredWidth > 0 && width > 0 && configuredWidth != width)
                    || (configuredHeight > 0 && height > 0 && configuredHeight != height);
            streamConfig = next;
        }
        if (changed) {
            release();
            listener.onDecoderNeedsKeyframe();
        }
        listener.onDecoderStatus("视频配置 " + streamConfig.codec + " / " + streamConfig.fps + "fps");
    }

    public synchronized void queueFrame(VideoFramePacket frame) {
        byte[] payload = frame.bytes;
        int payloadOffset = frame.payloadOffset;
        int payloadLength = frame.payloadLength;
        VideoFrameTelemetry telemetry = frame.telemetry;
        if (!surface.isValid()) {
            listener.onDecoderFrameDropped(
                    AndroidDropReason.SURFACE_UNAVAILABLE, telemetry);
            return;
        }
        if (!frame.hasAnnexBPayload()) {
            listener.onDecoderFrameDropped(
                    AndroidDropReason.MALFORMED_ANNEX_B, telemetry);
            return;
        }
        boolean hevc = streamConfig.isHevc();
        AnnexB.NalSummary summary = null;
        byte[] vps = null;
        byte[] sps = null;
        byte[] pps = null;
        if (codec == null) {
            summary = frame.nalSummary(streamConfig);
            vps = hevc ? summary.copyVps() : null;
            sps = summary.copySps();
            pps = summary.copyPps();
            if (sps == null) {
                long now = System.currentTimeMillis();
                if (now - lastMissingParameterLogMs >= 1000) {
                    lastMissingParameterLogMs = now;
                    Log.w(LOG_TAG, "decoder has no SPS; codec=" + streamConfig.codec
                            + " bytes=" + payloadLength
                            + " nalTypes=" + describeNalTypes(
                                    payload, payloadOffset, payloadLength, hevc));
                }
                listener.onDecoderNeedsKeyframe();
                return;
            }
            SpsParser.Size size = streamConfig.isHevc()
                    ? new SpsParser.Size(streamConfig.width, streamConfig.height)
                    : SpsParser.parseDimensions(sps);
            if (size == null || size.width <= 0 || size.height <= 0) {
                listener.onDecoderStatus("无法解析 H.264 SPS");
                listener.onDecoderNeedsKeyframe();
                return;
            }
            try {
                configure(size.width, size.height, vps, sps, pps);
            } catch (IOException | RuntimeException error) {
                String message = "解码器启动失败：" + error.getMessage();
                listener.onDecoderStatus(message);
                listener.onDecoderFrameDropped(
                        AndroidDropReason.DECODER_EXCEPTION, telemetry);
                listener.onDecoderCodecFailure(streamConfig.codec, message);
                return;
            }
        }

        submitOrHoldFrame(frame);
    }

    public void release() {
        MediaCodec activeCodec;
        HandlerThread callbackThread;
        synchronized (this) {
            activeCodec = codec;
            codec = null;
            callbackState.invalidate();
            pendingInputFrames.clear();
            referenceChainRecovery.reset();
            lastRuntimeInfo = null;
            callbackThread = renderedCallbackThread;
            renderedCallbackThread = null;
        }
        releaseCandidate(activeCodec);
        if (callbackThread != null) {
            callbackThread.quitSafely();
        }
    }

    private void configure(int width, int height, byte[] vps, byte[] sps, byte[] pps)
            throws IOException {
        List<DecoderSelectionPolicy.Candidate> candidates = decoderCandidates();
        List<DecoderSelectionPolicy.Attempt> attempts =
                DecoderSelectionPolicy.attempts(candidates, lowLatencyMode);
        Throwable lastError = null;
        String fallbackReason = "";
        DecoderSelectionPolicy.Attempt lastAttempt = null;
        for (DecoderSelectionPolicy.Attempt attempt : attempts) {
            lastAttempt = attempt;
            try {
                configureAttempt(width, height, vps, sps, pps, attempt);
            } catch (IOException | RuntimeException error) {
                lastError = error;
                if (attempt.enableLowLatency) {
                    fallbackReason = "lowLatencyConfigureFailed:"
                            + error.getClass().getSimpleName();
                    Log.w(LOG_TAG, "low-latency configure failed; retrying decoder without it"
                            + " decoder=" + attempt.decoderName, error);
                } else {
                    fallbackReason = "decoderConfigureFailed:"
                            + attempt.decoderName + ":"
                            + error.getClass().getSimpleName();
                    Log.w(LOG_TAG, "decoder configure failed; trying next candidate"
                            + " decoder=" + attempt.decoderName, error);
                }
                continue;
            }
            if (fallbackReason.length() == 0) {
                if (lowLatencyMode == DecoderLowLatencyMode.OFF) {
                    fallbackReason = "disabledByUser";
                } else if (!attempt.lowLatencySupported) {
                    fallbackReason = "unsupportedByDecoder";
                }
            }
            lastRuntimeInfo = new DecoderRuntimeInfo(
                    streamConfig.codec,
                    attempt.decoderName,
                    attempt.hardwareAccelerated,
                    attempt.softwareOnly,
                    attempt.vendor,
                    attempt.lowLatencySupported,
                    attempt.enableLowLatency,
                    true,
                    CodecCapabilities.decoderMaxFps(
                            streamConfig.mimeType, attempt.decoderName,
                            width, height, streamConfig.fps),
                    fallbackReason);
            listener.onDecoderReady(lastRuntimeInfo);
            listener.onDecoderStatus("正在接收 " + configuredWidth + "×" + configuredHeight
                    + " · " + streamConfig.codec + " · " + streamConfig.fps + "fps");
            return;
        }
        if (fallbackReason.length() == 0) {
            fallbackReason = "noDecoderCandidate";
        }
        lastRuntimeInfo = new DecoderRuntimeInfo(
                streamConfig.codec,
                lastAttempt == null ? "" : lastAttempt.decoderName,
                lastAttempt != null && lastAttempt.hardwareAccelerated,
                lastAttempt != null && lastAttempt.softwareOnly,
                lastAttempt != null && lastAttempt.vendor,
                lastAttempt != null && lastAttempt.lowLatencySupported,
                false,
                false,
                30,
                fallbackReason);
        listener.onDecoderConfigurationFailed(lastRuntimeInfo);
        throw new IOException("no usable decoder for " + streamConfig.mimeType,
                lastError);
    }

    private void configureAttempt(
            int width, int height, byte[] vps, byte[] sps, byte[] pps,
            DecoderSelectionPolicy.Attempt attempt) throws IOException {
        MediaCodec candidateCodec = null;
        HandlerThread candidateCallbackThread = null;
        try {
            candidateCodec = MediaCodec.createByCodecName(attempt.decoderName);
            final long callbackGeneration;
            synchronized (this) {
                callbackGeneration = callbackState.activate(candidateCodec);
            }
            MediaFormat format = decoderFormat(width, height, vps, sps, pps);
            if (attempt.enableLowLatency && android.os.Build.VERSION.SDK_INT >= 30) {
                format.setInteger(MediaFormat.KEY_LOW_LATENCY, 1);
            }
            candidateCodec.configure(format, surface, null, 0);
            HandlerThread callbackThread =
                    new HandlerThread("OpenDisplayFrameRendered");
            candidateCallbackThread = callbackThread;
            callbackThread.start();
            final MediaCodec callbackCodec = candidateCodec;
            candidateCodec.setCallback(new MediaCodec.Callback() {
                @Override
                public void onInputBufferAvailable(MediaCodec mediaCodec, int index) {
                    handleInputBufferAvailable(callbackGeneration, callbackCodec, index);
                }

                @Override
                public void onOutputBufferAvailable(
                        MediaCodec mediaCodec, int index, MediaCodec.BufferInfo info) {
                    handleOutputBufferAvailable(
                            callbackGeneration, callbackCodec, index, info);
                }

                @Override
                public void onError(MediaCodec mediaCodec, MediaCodec.CodecException error) {
                    handleCodecError(callbackGeneration, callbackCodec, error);
                }

                @Override
                public void onOutputFormatChanged(MediaCodec mediaCodec, MediaFormat format) {
                    handleOutputFormatChanged(callbackGeneration, callbackCodec, format);
                }
            }, new Handler(callbackThread.getLooper()));
            candidateCodec.setOnFrameRenderedListener(
                    (mediaCodec, presentationTimeUs, nanoTime) -> {
                        handleFrameRendered(
                                callbackGeneration, callbackCodec, presentationTimeUs);
                    },
                    new Handler(callbackThread.getLooper()));
            codec = candidateCodec;
            renderedCallbackThread = candidateCallbackThread;
            pendingInputFrames.clear();
            referenceChainRecovery.reset();
            candidateCodec.start();
            configuredWidth = width;
            configuredHeight = height;
            presentationUs = 0;
        } catch (IOException | RuntimeException error) {
            if (codec == candidateCodec) {
                codec = null;
                renderedCallbackThread = null;
                callbackState.invalidate();
                pendingInputFrames.clear();
                referenceChainRecovery.reset();
            }
            releaseCandidate(candidateCodec);
            if (candidateCallbackThread != null) {
                candidateCallbackThread.quitSafely();
            }
            throw error;
        }
    }

    private MediaFormat decoderFormat(
            int width, int height, byte[] vps, byte[] sps, byte[] pps) {
        MediaFormat format = MediaFormat.createVideoFormat(streamConfig.mimeType, width, height);
        format.setInteger(MediaFormat.KEY_MAX_INPUT_SIZE, Math.max(width * height, 1 << 20));
        format.setInteger(MediaFormat.KEY_PRIORITY, 0);
        if (android.os.Build.VERSION.SDK_INT >= 30) {
            format.setInteger(MediaFormat.KEY_ALLOW_FRAME_DROP, 1);
        }
        if (streamConfig.isHevc()) {
            java.io.ByteArrayOutputStream csd = new java.io.ByteArrayOutputStream();
            appendParameterSet(csd, vps);
            appendParameterSet(csd, sps);
            appendParameterSet(csd, pps);
            format.setByteBuffer("csd-0", java.nio.ByteBuffer.wrap(csd.toByteArray()));
        } else {
            if (sps != null) {
                format.setByteBuffer("csd-0", java.nio.ByteBuffer.wrap(AnnexB.withStartCode(sps)));
            }
            if (pps != null) {
                format.setByteBuffer("csd-1", java.nio.ByteBuffer.wrap(AnnexB.withStartCode(pps)));
            }
        }
        return format;
    }

    private List<DecoderSelectionPolicy.Candidate> decoderCandidates() {
        List<DecoderSelectionPolicy.Candidate> result = new ArrayList<>();
        boolean enumerationFailed = false;
        try {
            for (MediaCodecInfo info :
                    new MediaCodecList(MediaCodecList.ALL_CODECS).getCodecInfos()) {
                if (info.isEncoder() || !supportsType(info, streamConfig.mimeType)) {
                    continue;
                }
                String normalizedName =
                        info.getName().toLowerCase(java.util.Locale.US);
                if (streamConfig.isHevc()
                        && CodecCapabilities.isKnownBrokenHevcName(normalizedName)) {
                    continue;
                }
                result.add(candidateFromInfo(info));
            }
        } catch (RuntimeException error) {
            enumerationFailed = true;
            Log.w(LOG_TAG, "decoder enumeration failed; probing platform default", error);
        }
        if (result.isEmpty() && enumerationFailed) {
            MediaCodec probe = null;
            try {
                probe = MediaCodec.createDecoderByType(streamConfig.mimeType);
                result.add(candidateFromInfo(probe.getCodecInfo()));
            } catch (IOException | RuntimeException error) {
                Log.w(LOG_TAG, "default decoder probe failed", error);
            } finally {
                releaseCandidate(probe);
            }
        }
        return result;
    }

    private DecoderSelectionPolicy.Candidate candidateFromInfo(MediaCodecInfo info) {
        String normalizedName = info.getName().toLowerCase(java.util.Locale.US);
        boolean softwareOnly = CodecCapabilities.isSoftwareDecoderName(normalizedName);
        boolean hardwareAccelerated = !softwareOnly;
        boolean vendor = !softwareOnly;
        if (android.os.Build.VERSION.SDK_INT >= 29) {
            hardwareAccelerated = info.isHardwareAccelerated();
            softwareOnly = info.isSoftwareOnly();
            vendor = info.isVendor();
        }
        boolean lowLatencySupported = false;
        if (android.os.Build.VERSION.SDK_INT >= 30) {
            try {
                lowLatencySupported = info.getCapabilitiesForType(streamConfig.mimeType)
                        .isFeatureSupported(
                                MediaCodecInfo.CodecCapabilities.FEATURE_LowLatency);
            } catch (RuntimeException ignored) {
            }
        }
        return new DecoderSelectionPolicy.Candidate(
                info.getName(), hardwareAccelerated, softwareOnly, vendor,
                lowLatencySupported);
    }

    private static boolean supportsType(MediaCodecInfo info, String mimeType) {
        for (String supported : info.getSupportedTypes()) {
            if (supported.equalsIgnoreCase(mimeType)) {
                return true;
            }
        }
        return false;
    }

    private static void releaseCandidate(MediaCodec candidate) {
        if (candidate == null) {
            return;
        }
        try {
            candidate.stop();
        } catch (RuntimeException ignored) {
        }
        try {
            candidate.release();
        } catch (RuntimeException ignored) {
        }
    }

    private synchronized void submitOrHoldFrame(VideoFramePacket frame) {
        if (codec == null) {
            listener.onDecoderFrameDropped(
                    AndroidDropReason.CODEC_RECONFIGURE_DROP, frame.telemetry);
            return;
        }
        boolean wasAwaitingKeyframe = referenceChainRecovery.isAwaitingKeyframe();
        if (referenceChainRecovery.shouldReject(
                frame.keyframe, System.currentTimeMillis())) {
            listener.onDecoderFrameDropped(
                    AndroidDropReason.AWAITING_KEYFRAME_REJECTED, frame.telemetry);
            return;
        }
        if (wasAwaitingKeyframe && frame.keyframe) {
            listener.onDecoderRecoveryCompleted(
                    referenceChainRecovery.lastCompletedDurationMs());
        }
        Integer input = callbackState.pollInput();
        if (input == null) {
            if (pendingInputFrames.offer(frame)) {
                return;
            }
            listener.onDecoderPendingQueueOverflow();
            for (VideoFramePacket dropped : pendingInputFrames.clearAndReturn()) {
                listener.onDecoderFrameDropped(
                        AndroidDropReason.LATEST_SLOT_REPLACED, dropped.telemetry);
            }
            if (frame.keyframe) {
                pendingInputFrames.offer(frame);
            } else {
                breakReferenceChain(frame.telemetry);
            }
            return;
        }
        submitFrame(codec, input, frame);
    }

    private synchronized void handleInputBufferAvailable(
            long generation, MediaCodec activeCodec, int index) {
        if (!isActive(generation, activeCodec)) {
            return;
        }
        VideoFramePacket frame = pendingInputFrames.poll();
        if (frame == null) {
            if (!callbackState.offerInput(index)) {
                Log.w(LOG_TAG, "duplicate input buffer callback ignored generation="
                        + generation + " index=" + index);
                return;
            }
            return;
        }
        submitFrame(activeCodec, index, frame);
    }

    private void submitFrame(MediaCodec activeCodec, int input, VideoFramePacket frame) {
        try {
            java.nio.ByteBuffer buffer = activeCodec.getInputBuffer(input);
            if (buffer == null) {
                listener.onDecoderFrameDropped(
                        AndroidDropReason.DECODER_INPUT_UNAVAILABLE, frame.telemetry);
                returnInputBuffer(activeCodec, input);
                breakReferenceChain(frame.telemetry);
                return;
            }
            if (frame.payloadLength > buffer.capacity()) {
                listener.onDecoderStatus("视频帧过大，已丢弃");
                listener.onDecoderFrameDropped(
                        AndroidDropReason.DECODER_INPUT_OVERSIZE, frame.telemetry);
                returnInputBuffer(activeCodec, input);
                breakReferenceChain(frame.telemetry);
                return;
            }
            buffer.clear();
            buffer.put(frame.bytes, frame.payloadOffset, frame.payloadLength);
            long framePresentationUs = presentationUs;
            int flags = frame.keyframe ? MediaCodec.BUFFER_FLAG_KEY_FRAME : 0;
            activeCodec.queueInputBuffer(
                    input, 0, frame.payloadLength, framePresentationUs, flags);
            listener.onDecoderFrameSubmitted();
            callbackState.putTelemetry(framePresentationUs, frame.telemetry);
            presentationUs += 1_000_000L / Math.max(streamConfig.fps, 1);
        } catch (IllegalStateException error) {
            listener.onDecoderStatus("解码器异常，正在重建解码器");
            listener.onDecoderFrameDropped(
                    AndroidDropReason.DECODER_EXCEPTION, frame.telemetry);
            listener.onDecoderCodecFailure(
                    streamConfig.codec, "queueInputBuffer: " + error.getMessage());
        }
    }

    private void returnInputBuffer(MediaCodec activeCodec, int input) {
        try {
            activeCodec.queueInputBuffer(input, 0, 0, presentationUs, 0);
        } catch (IllegalStateException ignored) {
        }
    }

    private void breakReferenceChain(VideoFrameTelemetry telemetry) {
        if (!referenceChainRecovery.breakChain(System.currentTimeMillis())) {
            return;
        }
        for (VideoFramePacket pending : pendingInputFrames.clearAndReturn()) {
            listener.onDecoderFrameDropped(
                    AndroidDropReason.AWAITING_KEYFRAME_REJECTED,
                    pending.telemetry);
        }
        listener.onDecoderRecoveryStarted();
        listener.onDecoderFrameDropped(
                AndroidDropReason.REFERENCE_CHAIN_BROKEN, telemetry);
        listener.onDecoderNeedsKeyframe();
    }

    private synchronized void handleOutputBufferAvailable(
            long generation, MediaCodec activeCodec,
            int index, MediaCodec.BufferInfo info) {
        if (!isActive(generation, activeCodec)) {
            return;
        }
        listener.onDecoderFrameDecoded();
        try {
            activeCodec.releaseOutputBuffer(index, true);
        } catch (IllegalStateException error) {
            listener.onDecoderFrameDropped(AndroidDropReason.DECODER_EXCEPTION, null);
            listener.onDecoderCodecFailure(
                    streamConfig.codec, "releaseOutputBuffer: " + error.getMessage());
        }
    }

    private synchronized void handleOutputFormatChanged(
            long generation, MediaCodec activeCodec, MediaFormat format) {
        if (!isActive(generation, activeCodec)) {
            return;
        }
        if (format.containsKey(MediaFormat.KEY_WIDTH)) {
            configuredWidth = format.getInteger(MediaFormat.KEY_WIDTH);
        }
        if (format.containsKey(MediaFormat.KEY_HEIGHT)) {
            configuredHeight = format.getInteger(MediaFormat.KEY_HEIGHT);
        }
        listener.onDecoderStatus("正在接收 " + configuredWidth + "×" + configuredHeight
                + " · " + streamConfig.codec + " · " + streamConfig.fps + "fps");
    }

    private synchronized void handleCodecError(
            long generation, MediaCodec activeCodec, MediaCodec.CodecException error) {
        if (!isActive(generation, activeCodec)) {
            return;
        }
        listener.onDecoderStatus("解码器异常，正在恢复：" + error.getDiagnosticInfo());
        listener.onDecoderFrameDropped(AndroidDropReason.DECODER_EXCEPTION, null);
        listener.onDecoderCodecFailure(streamConfig.codec, error.getDiagnosticInfo());
    }

    private synchronized void handleFrameRendered(
            long generation, MediaCodec activeCodec, long presentationTimeUs) {
        if (!isActive(generation, activeCodec)) {
            return;
        }
        VideoFrameTelemetry telemetry = callbackState.removeTelemetry(presentationTimeUs);
        if (telemetry != null) {
            listener.onDecoderFrameRendered(telemetry);
        }
    }

    private boolean isActive(long generation, MediaCodec activeCodec) {
        return callbackState.isActive(generation, activeCodec) && codec == activeCodec;
    }

    synchronized int renderedTelemetrySizeForTesting() {
        return callbackState.telemetrySize();
    }

    synchronized long renderedTelemetryPeakForTesting() {
        return callbackState.telemetryPeak();
    }

    synchronized long renderedTelemetryEvictedForTesting() {
        return callbackState.telemetryEvicted();
    }

    private static void appendParameterSet(java.io.ByteArrayOutputStream out, byte[] parameterSet) {
        if (parameterSet == null) {
            return;
        }
        byte[] withStart = AnnexB.withStartCode(parameterSet);
        out.write(withStart, 0, withStart.length);
    }

    private static String describeNalTypes(
            byte[] payload, int offset, int length, boolean hevc) {
        StringBuilder result = new StringBuilder();
        int count = 0;
        int end = offset + length;
        int start = AnnexB.firstStartCode(payload, offset, length);
        while (start >= 0 && count < 12) {
            int nalOffset = start + 4;
            int next = AnnexB.firstStartCode(payload, nalOffset, end - nalOffset);
            int nalEnd = next >= 0 ? next : end;
            if (nalEnd <= nalOffset) {
                if (next < 0) break;
                start = next;
                continue;
            }
            if (count > 0) {
                result.append(',');
            }
            result.append(hevc
                    ? ((payload[nalOffset] >> 1) & 0x3F)
                    : (payload[nalOffset] & 0x1F));
            count++;
            if (next < 0) break;
            start = next;
        }
        return result.toString();
    }
}

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
import java.util.ArrayDeque;
import java.util.ArrayList;
import java.util.List;
import java.util.Queue;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.ConcurrentMap;

import app.opendisplay.android.protocol.AnnexB;
import app.opendisplay.android.protocol.SpsParser;

public final class H264SurfaceDecoder {
    private static final String LOG_TAG = "DisplayWeaveDecoder";
    private final Surface surface;
    private final DecoderLowLatencyMode lowLatencyMode;
    private volatile Listener listener;
    private MediaCodec codec;
    private int configuredWidth;
    private int configuredHeight;
    private long presentationUs;
    private VideoStreamConfig streamConfig = VideoStreamConfig.DEFAULT;
    private final Queue<VideoFrameTelemetry> pendingTelemetry = new ArrayDeque<>();
    private final ConcurrentMap<Long, VideoFrameTelemetry> renderedTelemetry = new ConcurrentHashMap<>();
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

    public synchronized void applyStreamConfig(String codecName, int fps, int width, int height) {
        VideoStreamConfig next = VideoStreamConfig.from(codecName, fps, width, height, 0);
        boolean changed = !streamConfig.codec.equals(next.codec) || streamConfig.fps != next.fps
                || (configuredWidth > 0 && width > 0 && configuredWidth != width)
                || (configuredHeight > 0 && height > 0 && configuredHeight != height);
        streamConfig = next;
        if (changed) {
            release();
            listener.onDecoderNeedsKeyframe();
        }
        listener.onDecoderStatus("视频配置 " + streamConfig.codec + " / " + streamConfig.fps + "fps");
    }

    public synchronized void queueFrame(byte[] wirePayload, VideoFrameTelemetry telemetry) {
        byte[] payload = AnnexB.stripTelemetryPrefix(wirePayload);
        if (!surface.isValid()) {
            listener.onDecoderFrameDropped(
                    AndroidDropReason.SURFACE_UNAVAILABLE, telemetry);
            return;
        }
        if (payload.length == 0 || AnnexB.nalUnits(payload).isEmpty()) {
            listener.onDecoderFrameDropped(
                    AndroidDropReason.MALFORMED_ANNEX_B, telemetry);
            return;
        }
        boolean hevc = streamConfig.isHevc();
        byte[] vps = hevc
                ? AnnexB.findNalUnit(payload, streamConfig.vpsNalType(), true)
                : null;
        byte[] sps = AnnexB.findNalUnit(payload, streamConfig.spsNalType(), hevc);
        byte[] pps = AnnexB.findNalUnit(payload, streamConfig.ppsNalType(), hevc);
        if (codec == null) {
            if (sps == null) {
                long now = System.currentTimeMillis();
                if (now - lastMissingParameterLogMs >= 1000) {
                    lastMissingParameterLogMs = now;
                    Log.w(LOG_TAG, "decoder has no SPS; codec=" + streamConfig.codec
                            + " bytes=" + payload.length
                            + " nalTypes=" + describeNalTypes(payload, hevc));
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
                release();
                return;
            }
        }

        try {
            int input = codec.dequeueInputBuffer(0);
            if (input < 0) {
                listener.onDecoderFrameDropped(
                        AndroidDropReason.DECODER_INPUT_UNAVAILABLE, telemetry);
                return;
            }
            java.nio.ByteBuffer buffer = codec.getInputBuffer(input);
            if (buffer == null) {
                listener.onDecoderFrameDropped(
                        AndroidDropReason.DECODER_INPUT_UNAVAILABLE, telemetry);
                return;
            }
            if (payload.length > buffer.capacity()) {
                listener.onDecoderStatus("视频帧过大，已丢弃");
                listener.onDecoderFrameDropped(
                        AndroidDropReason.DECODER_INPUT_OVERSIZE, telemetry);
                return;
            }
            buffer.clear();
            buffer.put(payload);
            int flags = containsNalType(payload, streamConfig.keyframeNalType(), streamConfig.isHevc())
                    ? MediaCodec.BUFFER_FLAG_KEY_FRAME : 0;
            codec.queueInputBuffer(input, 0, payload.length, presentationUs, flags);
            pendingTelemetry.add(telemetry);
            presentationUs += 1_000_000L / Math.max(streamConfig.fps, 1);
            drainOutput();
        } catch (IllegalStateException error) {
            listener.onDecoderStatus("解码器异常，正在请求关键帧");
            listener.onDecoderFrameDropped(
                    AndroidDropReason.DECODER_EXCEPTION, telemetry);
            release();
            listener.onDecoderNeedsKeyframe();
        }
    }

    public synchronized void release() {
        if (codec != null) {
            MediaCodec activeCodec = codec;
            codec = null;
            releaseCandidate(activeCodec);
            lastRuntimeInfo = null;
            pendingTelemetry.clear();
            renderedTelemetry.clear();
        }
        if (renderedCallbackThread != null) {
            renderedCallbackThread.quitSafely();
            renderedCallbackThread = null;
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
            MediaFormat format = decoderFormat(width, height, vps, sps, pps);
            if (attempt.enableLowLatency && android.os.Build.VERSION.SDK_INT >= 30) {
                format.setInteger(MediaFormat.KEY_LOW_LATENCY, 1);
            }
            candidateCodec.configure(format, surface, null, 0);
            HandlerThread callbackThread =
                    new HandlerThread("OpenDisplayFrameRendered");
            candidateCallbackThread = callbackThread;
            callbackThread.start();
            candidateCodec.setOnFrameRenderedListener(
                    (mediaCodec, presentationTimeUs, nanoTime) -> {
                        VideoFrameTelemetry telemetry =
                                renderedTelemetry.remove(presentationTimeUs);
                        listener.onDecoderFrameRendered(telemetry);
                    },
                    new Handler(callbackThread.getLooper()));
            candidateCodec.start();
            codec = candidateCodec;
            renderedCallbackThread = candidateCallbackThread;
            configuredWidth = width;
            configuredHeight = height;
            presentationUs = 0;
        } catch (IOException | RuntimeException error) {
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

    private void drainOutput() {
        MediaCodec.BufferInfo info = new MediaCodec.BufferInfo();
        while (true) {
            int output = codec.dequeueOutputBuffer(info, 0);
            if (output >= 0) {
                VideoFrameTelemetry telemetry = pendingTelemetry.poll();
                if (telemetry != null) {
                    renderedTelemetry.put(info.presentationTimeUs, telemetry);
                }
                listener.onDecoderFrameDecoded();
                codec.releaseOutputBuffer(output, true);
            } else if (output == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED) {
                MediaFormat format = codec.getOutputFormat();
                configuredWidth = format.getInteger(MediaFormat.KEY_WIDTH);
                configuredHeight = format.getInteger(MediaFormat.KEY_HEIGHT);
                listener.onDecoderStatus("正在接收 " + configuredWidth + "×" + configuredHeight
                        + " · " + streamConfig.codec + " · " + streamConfig.fps + "fps");
            } else {
                return;
            }
        }
    }

    private static void appendParameterSet(java.io.ByteArrayOutputStream out, byte[] parameterSet) {
        if (parameterSet == null) {
            return;
        }
        byte[] withStart = AnnexB.withStartCode(parameterSet);
        out.write(withStart, 0, withStart.length);
    }

    private static boolean containsNalType(byte[] payload, int type, boolean hevc) {
        for (byte[] unit : AnnexB.nalUnits(payload)) {
            if (!hevc && unit.length > 0 && (unit[0] & 0x1F) == type) {
                return true;
            }
            if (hevc && unit.length > 1 && ((unit[0] >> 1) & 0x3F) == type) {
                return true;
            }
        }
        return false;
    }

    private static String describeNalTypes(byte[] payload, boolean hevc) {
        StringBuilder result = new StringBuilder();
        int count = 0;
        for (byte[] unit : AnnexB.nalUnits(payload)) {
            if (unit.length == 0) {
                continue;
            }
            if (count > 0) {
                result.append(',');
            }
            result.append(hevc ? ((unit[0] >> 1) & 0x3F) : (unit[0] & 0x1F));
            count++;
            if (count == 12) {
                break;
            }
        }
        return result.toString();
    }
}

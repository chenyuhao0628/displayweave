package app.opendisplay.android;

import android.media.MediaCodec;
import android.media.MediaFormat;
import android.os.Handler;
import android.os.HandlerThread;
import android.util.Log;
import android.view.Surface;

import java.io.IOException;
import java.util.ArrayDeque;
import java.util.Queue;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.ConcurrentMap;

import app.opendisplay.android.protocol.AnnexB;
import app.opendisplay.android.protocol.SpsParser;

public final class H264SurfaceDecoder {
    private static final String LOG_TAG = "DisplayWeaveDecoder";
    private final Surface surface;
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
        void onDecoderNeedsKeyframe();
        void onDecoderCodecFailure(String codec, String message);
        void onDecoderFrameDropped();
        void onDecoderFrameDecoded();
        void onDecoderFrameRendered(VideoFrameTelemetry telemetry);
    }

    public H264SurfaceDecoder(Surface surface, Listener listener) {
        this.surface = surface;
        this.listener = listener;
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
                listener.onDecoderCodecFailure(streamConfig.codec, message);
                release();
                return;
            }
        }

        try {
            int input = codec.dequeueInputBuffer(0);
            if (input < 0) {
                listener.onDecoderFrameDropped();
                return;
            }
            java.nio.ByteBuffer buffer = codec.getInputBuffer(input);
            if (buffer == null || payload.length > buffer.capacity()) {
                listener.onDecoderStatus("视频帧过大，已丢弃");
                listener.onDecoderFrameDropped();
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
            listener.onDecoderFrameDropped();
            release();
            listener.onDecoderNeedsKeyframe();
        }
    }

    public synchronized void release() {
        if (codec != null) {
            try {
                codec.stop();
            } catch (RuntimeException ignored) {
            }
            codec.release();
            codec = null;
            lastRuntimeInfo = null;
            pendingTelemetry.clear();
            renderedTelemetry.clear();
        }
        if (renderedCallbackThread != null) {
            renderedCallbackThread.quitSafely();
            renderedCallbackThread = null;
        }
    }

    private void configure(int width, int height, byte[] vps, byte[] sps, byte[] pps) throws IOException {
        codec = MediaCodec.createDecoderByType(streamConfig.mimeType);
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
        codec.configure(format, surface, null, 0);
        renderedCallbackThread = new HandlerThread("OpenDisplayFrameRendered");
        renderedCallbackThread.start();
        codec.setOnFrameRenderedListener((mediaCodec, presentationTimeUs, nanoTime) -> {
            VideoFrameTelemetry telemetry = renderedTelemetry.remove(presentationTimeUs);
            listener.onDecoderFrameRendered(telemetry);
        }, new Handler(renderedCallbackThread.getLooper()));
        codec.start();
        configuredWidth = width;
        configuredHeight = height;
        presentationUs = 0;
        lastRuntimeInfo = runtimeInfo();
        listener.onDecoderReady(lastRuntimeInfo);
        listener.onDecoderStatus("正在接收 " + configuredWidth + "×" + configuredHeight
                + " · " + streamConfig.codec + " · " + streamConfig.fps + "fps");
    }

    private DecoderRuntimeInfo runtimeInfo() {
        android.media.MediaCodecInfo info = codec.getCodecInfo();
        boolean hardwareAccelerated = false;
        boolean softwareOnly = false;
        boolean vendor = false;
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
                                android.media.MediaCodecInfo.CodecCapabilities.FEATURE_LowLatency);
            } catch (IllegalArgumentException ignored) {
            }
        }
        return new DecoderRuntimeInfo(
                streamConfig.codec,
                codec.getName(),
                hardwareAccelerated,
                softwareOnly,
                vendor,
                lowLatencySupported,
                false);
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

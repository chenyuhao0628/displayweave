package app.opendisplay.android;

public final class StreamMetrics {
    public final int receiverFps;
    public final int renderedFps;
    public final int decodedFps;
    public final double rttMs;
    public final double inputP50Ms;
    public final int macCaptureFps;
    public final int requestedFps;
    public final String codec;
    public final int bitrate;
    public final int droppedFramesAndroid;
    public final int queueDepthAndroid;
    public final float androidDisplayRefreshRate;
    public final int latestFrameAgeMs;
    public final int endToEndLatencyMs;
    public final int decodeLatencyMs;
    public final int actualVirtualDisplayRefreshRate;
    public final int encodedFps;
    public final int sentFps;
    public final int averageFrameSize;
    public final int encodeLatencyMs;
    public final int queueDepthMac;
    public final int droppedFramesMac;
    public final String transport;

    public StreamMetrics(int receiverFps, double rttMs, double inputP50Ms, int macCaptureFps) {
        this(receiverFps, receiverFps, receiverFps, rttMs, inputP50Ms, macCaptureFps,
                60, "h264", 0, 0, 0, 60f, 0, 0, 0);
    }

    public StreamMetrics(int receiverFps, int renderedFps, double rttMs, double inputP50Ms,
                         int macCaptureFps, int requestedFps, String codec, int bitrate,
                         int droppedFramesAndroid, int queueDepthAndroid,
                         float androidDisplayRefreshRate) {
        this(receiverFps, renderedFps, renderedFps, rttMs, inputP50Ms, macCaptureFps,
                requestedFps, codec, bitrate, droppedFramesAndroid, queueDepthAndroid,
                androidDisplayRefreshRate, 0, 0, 0);
    }

    public StreamMetrics(int receiverFps, int renderedFps, int decodedFps,
                         double rttMs, double inputP50Ms, int macCaptureFps,
                         int requestedFps, String codec, int bitrate,
                         int droppedFramesAndroid, int queueDepthAndroid,
                         float androidDisplayRefreshRate) {
        this(receiverFps, renderedFps, decodedFps, rttMs, inputP50Ms, macCaptureFps,
                requestedFps, codec, bitrate, droppedFramesAndroid, queueDepthAndroid,
                androidDisplayRefreshRate, 0, 0, 0);
    }

    public StreamMetrics(int receiverFps, int renderedFps, double rttMs, double inputP50Ms,
                         int macCaptureFps, int requestedFps, String codec, int bitrate,
                         int droppedFramesAndroid, int queueDepthAndroid,
                         float androidDisplayRefreshRate, int latestFrameAgeMs,
                         int endToEndLatencyMs, int decodeLatencyMs) {
        this(receiverFps, renderedFps, renderedFps, rttMs, inputP50Ms, macCaptureFps,
                requestedFps, codec, bitrate, droppedFramesAndroid, queueDepthAndroid,
                androidDisplayRefreshRate, latestFrameAgeMs, endToEndLatencyMs,
                decodeLatencyMs, 60, 0, 0, 0, 0, 0, 0, "wifi");
    }

    public StreamMetrics(int receiverFps, int renderedFps, int decodedFps,
                         double rttMs, double inputP50Ms, int macCaptureFps,
                         int requestedFps, String codec, int bitrate,
                         int droppedFramesAndroid, int queueDepthAndroid,
                         float androidDisplayRefreshRate, int latestFrameAgeMs,
                         int endToEndLatencyMs, int decodeLatencyMs) {
        this(receiverFps, renderedFps, decodedFps, rttMs, inputP50Ms, macCaptureFps,
                requestedFps, codec, bitrate, droppedFramesAndroid, queueDepthAndroid,
                androidDisplayRefreshRate, latestFrameAgeMs, endToEndLatencyMs,
                decodeLatencyMs, 60, 0, 0, 0, 0, 0, 0, "wifi");
    }

    public StreamMetrics(int receiverFps, int renderedFps, int decodedFps,
                         double rttMs, double inputP50Ms, int macCaptureFps,
                         int requestedFps, String codec, int bitrate,
                         int droppedFramesAndroid, int queueDepthAndroid,
                         float androidDisplayRefreshRate, int latestFrameAgeMs,
                         int endToEndLatencyMs, int decodeLatencyMs,
                         int actualVirtualDisplayRefreshRate, int encodedFps, int sentFps,
                         int averageFrameSize, int encodeLatencyMs, int queueDepthMac,
                         int droppedFramesMac, String transport) {
        this.receiverFps = receiverFps;
        this.renderedFps = renderedFps;
        this.decodedFps = decodedFps;
        this.rttMs = rttMs;
        this.inputP50Ms = inputP50Ms;
        this.macCaptureFps = macCaptureFps;
        this.requestedFps = requestedFps;
        this.codec = codec == null ? "h264" : codec;
        this.bitrate = bitrate;
        this.droppedFramesAndroid = droppedFramesAndroid;
        this.queueDepthAndroid = queueDepthAndroid;
        this.androidDisplayRefreshRate = androidDisplayRefreshRate;
        this.latestFrameAgeMs = latestFrameAgeMs;
        this.endToEndLatencyMs = endToEndLatencyMs;
        this.decodeLatencyMs = decodeLatencyMs;
        this.actualVirtualDisplayRefreshRate = actualVirtualDisplayRefreshRate;
        this.encodedFps = encodedFps;
        this.sentFps = sentFps;
        this.averageFrameSize = averageFrameSize;
        this.encodeLatencyMs = encodeLatencyMs;
        this.queueDepthMac = queueDepthMac;
        this.droppedFramesMac = droppedFramesMac;
        this.transport = transport == null ? "wifi" : transport;
    }
}

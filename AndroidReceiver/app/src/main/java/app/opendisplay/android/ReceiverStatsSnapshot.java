package app.opendisplay.android;

import java.util.LinkedHashMap;
import java.util.Map;

import app.opendisplay.android.protocol.LengthPrefixedProtocol;

public final class ReceiverStatsSnapshot {
    public final long timestamp;
    public final String deviceModel;
    public final String transport;
    public final String codec;
    public final int width;
    public final int height;
    public final int requestedFps;
    public final double actualAndroidDisplayRefreshRate;
    public final int receivedFps;
    public final int decodedFps;
    public final int renderedFps;
    public final double rttMs;
    public final Double clockOffsetMs;
    public final Double offsetConfidenceMs;
    public final Double clockRttMs;
    public final String clockState;
    public final Double frameAgeAvgMs;
    public final Long frameAgeLatestMs;
    public final Long frameAgeP50Ms;
    public final Long frameAgeP95Ms;
    public final Long frameAgeP99Ms;
    public final Double estimatedE2ELatencyMs;
    public final Double sendToRenderEstimatedMs;
    public final int androidQueueDepth;
    public final int androidDroppedFrames;
    public final Double inputP50Ms;
    public final Double inputP95Ms;

    public ReceiverStatsSnapshot(
            long timestamp, String deviceModel, String transport, String codec,
            int width, int height, int requestedFps, double actualAndroidDisplayRefreshRate,
            int receivedFps, int decodedFps, int renderedFps, double rttMs,
            Double clockOffsetMs, Double offsetConfidenceMs, Double clockRttMs,
            String clockState, Double frameAgeAvgMs, Long frameAgeLatestMs,
            Long frameAgeP50Ms, Long frameAgeP95Ms, Long frameAgeP99Ms,
            Double estimatedE2ELatencyMs, Double sendToRenderEstimatedMs,
            int androidQueueDepth, int androidDroppedFrames,
            Double inputP50Ms, Double inputP95Ms) {
        this.timestamp = timestamp;
        this.deviceModel = deviceModel;
        this.transport = transport;
        this.codec = codec;
        this.width = width;
        this.height = height;
        this.requestedFps = requestedFps;
        this.actualAndroidDisplayRefreshRate = actualAndroidDisplayRefreshRate;
        this.receivedFps = receivedFps;
        this.decodedFps = decodedFps;
        this.renderedFps = renderedFps;
        this.rttMs = rttMs;
        this.clockOffsetMs = clockOffsetMs;
        this.offsetConfidenceMs = offsetConfidenceMs;
        this.clockRttMs = clockRttMs;
        this.clockState = clockState;
        this.frameAgeAvgMs = frameAgeAvgMs;
        this.frameAgeLatestMs = frameAgeLatestMs;
        this.frameAgeP50Ms = frameAgeP50Ms;
        this.frameAgeP95Ms = frameAgeP95Ms;
        this.frameAgeP99Ms = frameAgeP99Ms;
        this.estimatedE2ELatencyMs = estimatedE2ELatencyMs;
        this.sendToRenderEstimatedMs = sendToRenderEstimatedMs;
        this.androidQueueDepth = androidQueueDepth;
        this.androidDroppedFrames = androidDroppedFrames;
        this.inputP50Ms = inputP50Ms;
        this.inputP95Ms = inputP95Ms;
    }

    public String toJson() {
        Map<String, Object> values = new LinkedHashMap<>();
        values.put("timestamp", timestamp);
        values.put("deviceModel", safe(deviceModel));
        values.put("transport", safe(transport));
        values.put("codec", safe(codec));
        values.put("width", width);
        values.put("height", height);
        values.put("requestedFps", requestedFps);
        values.put("actualAndroidDisplayRefreshRate", actualAndroidDisplayRefreshRate);
        values.put("receivedFps", receivedFps);
        values.put("decodedFps", decodedFps);
        values.put("renderedFps", renderedFps);
        values.put("rttMs", rttMs);
        values.put("clockOffsetMs", clockOffsetMs);
        values.put("offsetConfidenceMs", offsetConfidenceMs);
        values.put("clockRttMs", clockRttMs);
        values.put("clockState", safe(clockState));
        values.put("frameAgeAvgMs", frameAgeAvgMs);
        values.put("frameAgeLatestMs", frameAgeLatestMs);
        values.put("frameAgeP50Ms", frameAgeP50Ms);
        values.put("frameAgeP95Ms", frameAgeP95Ms);
        values.put("frameAgeP99Ms", frameAgeP99Ms);
        values.put("estimatedE2ELatencyMs", estimatedE2ELatencyMs);
        values.put("sendToRenderEstimatedMs", sendToRenderEstimatedMs);
        values.put("androidQueueDepth", androidQueueDepth);
        values.put("androidDroppedFrames", androidDroppedFrames);
        values.put("inputP50Ms", inputP50Ms);
        values.put("inputP95Ms", inputP95Ms);
        return LengthPrefixedProtocol.statsJson(values);
    }

    private static String safe(String value) {
        return value == null ? "" : value;
    }
}

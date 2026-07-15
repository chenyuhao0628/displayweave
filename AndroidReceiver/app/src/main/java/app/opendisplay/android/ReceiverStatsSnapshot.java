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
    public final double requestedSurfaceFrameRate;
    public final double actualAndroidDisplayRefreshRate;
    public final int receivedFps;
    public final int decodedFps;
    public final int renderedFps;
    public final int receivedFrames;
    public final int submittedToMediaCodecFrames;
    public final int pendingSlotReplaceCount;
    public final int referenceChainBreakCount;
    public final long awaitingKeyframeDurationMs;
    public final int keyframeRequestCount;
    public final int keyframeReceivedCount;
    public final int decodedFrames;
    public final int renderedFrames;
    public final Double rttMs;
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
    public final int pendingEncodesMac;
    public final int totalPendingWorkMac;
    public final int pendingEncodePeak;
    public final Double inputP50Ms;
    public final Double inputP95Ms;
    public final long currentFrameBytes;
    public final long maxFrameBytesObserved;
    public final long currentKeyframeBytes;
    public final long maxKeyframeBytesObserved;
    public final long oversizeFrameCount;
    public final long invalidFrameLengthCount;
    public final long allocatedFrameBytes;
    public final long bufferReuseCount;
    public final long bufferPoolMiss;
    public final long gcCount;
    public final long gcTimeMs;
    public final Integer thermalStatus;
    public final Boolean powerSaver;
    public final Double batteryTemperature;
    public final Integer batteryLevel;
    public final Boolean charging;
    public final String decoderName;
    public final Boolean hardwareAccelerated;
    public final Boolean softwareOnly;
    public final Boolean vendor;
    public final Boolean lowLatencySupported;
    public final Boolean lowLatencyEnabled;
    public final Boolean decoderConfigureSuccess;
    public final Integer selectedDecoderMaxFps;
    public final String decoderFallbackReason;
    public final String decoderLowLatencyMode;
    public final String frameRateApplyResult;
    public final String wifiLowLatencyMode;
    public final boolean wifiLowLatencyRequested;
    public final boolean wifiLowLatencyAcquired;
    public final boolean wifiLowLatencyActive;
    public final String wifiLowLatencyReleaseReason;
    public final AndroidDropTracker.Snapshot androidDropMetrics;

    public ReceiverStatsSnapshot(
            long timestamp, String deviceModel, String transport, String codec,
            int width, int height, int requestedFps, double requestedSurfaceFrameRate,
            double actualAndroidDisplayRefreshRate,
            int receivedFps, int decodedFps, int renderedFps,
            int receivedFrames, int submittedToMediaCodecFrames,
            int pendingSlotReplaceCount, int referenceChainBreakCount,
            long awaitingKeyframeDurationMs, int keyframeRequestCount,
            int keyframeReceivedCount, int decodedFrames, int renderedFrames,
            Double rttMs,
            Double clockOffsetMs, Double offsetConfidenceMs, Double clockRttMs,
            String clockState, Double frameAgeAvgMs, Long frameAgeLatestMs,
            Long frameAgeP50Ms, Long frameAgeP95Ms, Long frameAgeP99Ms,
            Double estimatedE2ELatencyMs, Double sendToRenderEstimatedMs,
            int androidQueueDepth, int androidDroppedFrames,
            int pendingEncodesMac, int totalPendingWorkMac, int pendingEncodePeak,
            Double inputP50Ms, Double inputP95Ms,
            long currentFrameBytes, long maxFrameBytesObserved,
            long currentKeyframeBytes, long maxKeyframeBytesObserved,
            long oversizeFrameCount, long invalidFrameLengthCount,
            long allocatedFrameBytes, long bufferReuseCount,
            long bufferPoolMiss, long gcCount, long gcTimeMs,
            Integer thermalStatus, Boolean powerSaver, Double batteryTemperature,
            Integer batteryLevel, Boolean charging,
            String decoderName, Boolean hardwareAccelerated, Boolean softwareOnly,
            Boolean vendor, Boolean lowLatencySupported, Boolean lowLatencyEnabled,
            Boolean decoderConfigureSuccess, Integer selectedDecoderMaxFps,
            String decoderFallbackReason,
            String decoderLowLatencyMode, String frameRateApplyResult,
            String wifiLowLatencyMode, boolean wifiLowLatencyRequested,
            boolean wifiLowLatencyAcquired, boolean wifiLowLatencyActive,
            String wifiLowLatencyReleaseReason,
            AndroidDropTracker.Snapshot androidDropMetrics) {
        this.timestamp = timestamp;
        this.deviceModel = deviceModel;
        this.transport = transport;
        this.codec = codec;
        this.width = width;
        this.height = height;
        this.requestedFps = requestedFps;
        this.requestedSurfaceFrameRate = requestedSurfaceFrameRate;
        this.actualAndroidDisplayRefreshRate = actualAndroidDisplayRefreshRate;
        this.receivedFps = receivedFps;
        this.decodedFps = decodedFps;
        this.renderedFps = renderedFps;
        this.receivedFrames = receivedFrames;
        this.submittedToMediaCodecFrames = submittedToMediaCodecFrames;
        this.pendingSlotReplaceCount = pendingSlotReplaceCount;
        this.referenceChainBreakCount = referenceChainBreakCount;
        this.awaitingKeyframeDurationMs = awaitingKeyframeDurationMs;
        this.keyframeRequestCount = keyframeRequestCount;
        this.keyframeReceivedCount = keyframeReceivedCount;
        this.decodedFrames = decodedFrames;
        this.renderedFrames = renderedFrames;
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
        this.pendingEncodesMac = pendingEncodesMac;
        this.totalPendingWorkMac = totalPendingWorkMac;
        this.pendingEncodePeak = pendingEncodePeak;
        this.inputP50Ms = inputP50Ms;
        this.inputP95Ms = inputP95Ms;
        this.currentFrameBytes = currentFrameBytes;
        this.maxFrameBytesObserved = maxFrameBytesObserved;
        this.currentKeyframeBytes = currentKeyframeBytes;
        this.maxKeyframeBytesObserved = maxKeyframeBytesObserved;
        this.oversizeFrameCount = oversizeFrameCount;
        this.invalidFrameLengthCount = invalidFrameLengthCount;
        this.allocatedFrameBytes = allocatedFrameBytes;
        this.bufferReuseCount = bufferReuseCount;
        this.bufferPoolMiss = bufferPoolMiss;
        this.gcCount = gcCount;
        this.gcTimeMs = gcTimeMs;
        this.thermalStatus = thermalStatus;
        this.powerSaver = powerSaver;
        this.batteryTemperature = batteryTemperature;
        this.batteryLevel = batteryLevel;
        this.charging = charging;
        this.decoderName = decoderName;
        this.hardwareAccelerated = hardwareAccelerated;
        this.softwareOnly = softwareOnly;
        this.vendor = vendor;
        this.lowLatencySupported = lowLatencySupported;
        this.lowLatencyEnabled = lowLatencyEnabled;
        this.decoderConfigureSuccess = decoderConfigureSuccess;
        this.selectedDecoderMaxFps = selectedDecoderMaxFps;
        this.decoderFallbackReason = decoderFallbackReason;
        this.decoderLowLatencyMode = decoderLowLatencyMode;
        this.frameRateApplyResult = frameRateApplyResult;
        this.wifiLowLatencyMode = wifiLowLatencyMode;
        this.wifiLowLatencyRequested = wifiLowLatencyRequested;
        this.wifiLowLatencyAcquired = wifiLowLatencyAcquired;
        this.wifiLowLatencyActive = wifiLowLatencyActive;
        this.wifiLowLatencyReleaseReason = wifiLowLatencyReleaseReason;
        this.androidDropMetrics = androidDropMetrics;
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
        values.put("requestedSurfaceFrameRate", requestedSurfaceFrameRate);
        values.put("actualAndroidDisplayRefreshRate", actualAndroidDisplayRefreshRate);
        values.put("receivedFps", receivedFps);
        values.put("decodedFps", decodedFps);
        values.put("renderedFps", renderedFps);
        values.put("receivedFrames", receivedFrames);
        values.put("submittedToMediaCodecFrames", submittedToMediaCodecFrames);
        values.put("pendingSlotReplaceCount", pendingSlotReplaceCount);
        values.put("referenceChainBreakCount", referenceChainBreakCount);
        values.put("awaitingKeyframeDurationMs", awaitingKeyframeDurationMs);
        values.put("keyframeRequestCount", keyframeRequestCount);
        values.put("keyframeReceivedCount", keyframeReceivedCount);
        values.put("decodedFrames", decodedFrames);
        values.put("renderedFrames", renderedFrames);
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
        values.put("pendingEncodesMac", pendingEncodesMac);
        values.put("totalPendingWorkMac", totalPendingWorkMac);
        values.put("pendingEncodePeak", pendingEncodePeak);
        values.put("inputP50Ms", inputP50Ms);
        values.put("inputP95Ms", inputP95Ms);
        values.put("currentFrameBytes", currentFrameBytes);
        values.put("maxFrameBytesObserved", maxFrameBytesObserved);
        values.put("currentKeyframeBytes", currentKeyframeBytes);
        values.put("maxKeyframeBytesObserved", maxKeyframeBytesObserved);
        values.put("oversizeFrameCount", oversizeFrameCount);
        values.put("invalidFrameLengthCount", invalidFrameLengthCount);
        values.put("allocatedFrameBytes", allocatedFrameBytes);
        values.put("bufferReuseCount", bufferReuseCount);
        values.put("bufferPoolMiss", bufferPoolMiss);
        values.put("gcCount", gcCount);
        values.put("gcTimeMs", gcTimeMs);
        values.put("thermalStatus", thermalStatus);
        values.put("powerSaver", powerSaver);
        values.put("batteryTemperature", batteryTemperature);
        values.put("batteryLevel", batteryLevel);
        values.put("charging", charging);
        values.put("decoderName", decoderName);
        values.put("hardwareAccelerated", hardwareAccelerated);
        values.put("softwareOnly", softwareOnly);
        values.put("vendor", vendor);
        values.put("lowLatencySupported", lowLatencySupported);
        values.put("lowLatencyEnabled", lowLatencyEnabled);
        values.put("decoderConfigureSuccess", decoderConfigureSuccess);
        values.put("selectedDecoderMaxFps", selectedDecoderMaxFps);
        values.put("decoderFallbackReason", decoderFallbackReason);
        values.put("decoderLowLatencyMode", decoderLowLatencyMode);
        values.put("frameRateApplyResult", safe(frameRateApplyResult));
        values.put("wifiLowLatencyMode", safe(wifiLowLatencyMode));
        values.put("wifiLowLatencyRequested", wifiLowLatencyRequested);
        values.put("wifiLowLatencyAcquired", wifiLowLatencyAcquired);
        values.put("wifiLowLatencyActive", wifiLowLatencyActive);
        values.put("wifiLowLatencyReleaseReason", safe(wifiLowLatencyReleaseReason));
        if (androidDropMetrics != null) {
            values.put("androidDropCountsWindow",
                    androidDropMetrics.windowCountsMap());
            values.put("androidDropCountsTotal",
                    androidDropMetrics.totalCountsMap());
            values.put("androidCongestionDrops",
                    androidDropMetrics.congestionRelevantWindowCount);
            values.put("androidDropTotal", androidDropMetrics.totalDropCount);
            values.put("androidLastDrop", androidDropMetrics.lastEvent == null
                    ? null : androidDropMetrics.lastEvent.asMap());
        }
        return LengthPrefixedProtocol.statsJson(values);
    }

    private static String safe(String value) {
        return value == null ? "" : value;
    }
}

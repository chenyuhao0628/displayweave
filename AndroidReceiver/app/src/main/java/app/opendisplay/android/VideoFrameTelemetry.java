package app.opendisplay.android;

import app.opendisplay.android.protocol.AnnexB;

public final class VideoFrameTelemetry {
    public static final long MISSING_MS = -1L;

    public final long captureMacMs;
    public final long sendMacMs;
    public final long receivedAndroidMs;
    public final long sessionEpoch;
    public final long configVersion;
    public final long frameSequence;

    private VideoFrameTelemetry(long captureMacMs, long sendMacMs, long receivedAndroidMs,
                                long sessionEpoch, long configVersion, long frameSequence) {
        this.captureMacMs = captureMacMs;
        this.sendMacMs = sendMacMs;
        this.receivedAndroidMs = receivedAndroidMs;
        this.sessionEpoch = sessionEpoch;
        this.configVersion = configVersion;
        this.frameSequence = frameSequence;
    }

    public static VideoFrameTelemetry fromWirePayload(byte[] payload, long receivedAndroidMs) {
        String prefix = AnnexB.telemetryPrefix(payload);
        if (prefix == null) {
            return new VideoFrameTelemetry(
                    MISSING_MS, MISSING_MS, receivedAndroidMs,
                    MISSING_MS, MISSING_MS, MISSING_MS);
        }
        return new VideoFrameTelemetry(
                parseLongField(prefix, "cap"),
                parseLongField(prefix, "snd"),
                receivedAndroidMs,
                parseLongField(prefix, "se"),
                parseLongField(prefix, "cv"),
                parseLongField(prefix, "fs"));
    }

    public long latestFrameAgeMs(long nowAndroidMs) {
        return Math.max(0L, nowAndroidMs - receivedAndroidMs);
    }

    public long endToEndLatencyMs(long nowAndroidMs, Double macClockOffsetMs) {
        if (captureMacMs < 0 || macClockOffsetMs == null) {
            return MISSING_MS;
        }
        long nowMacMs = Math.round(nowAndroidMs + macClockOffsetMs);
        return Math.max(0L, nowMacMs - captureMacMs);
    }

    public long decodeLatencyMs(long nowAndroidMs, Double macClockOffsetMs) {
        if (sendMacMs < 0 || macClockOffsetMs == null) {
            return MISSING_MS;
        }
        long nowMacMs = Math.round(nowAndroidMs + macClockOffsetMs);
        return Math.max(0L, nowMacMs - sendMacMs);
    }

    private static long parseLongField(String json, String field) {
        String key = "\"" + field + "\":";
        int start = json.indexOf(key);
        if (start < 0) {
            return MISSING_MS;
        }
        start += key.length();
        int end = start;
        while (end < json.length()) {
            char c = json.charAt(end);
            if ((c < '0' || c > '9') && c != '-') {
                break;
            }
            end++;
        }
        if (end == start) {
            return MISSING_MS;
        }
        try {
            return Long.parseLong(json.substring(start, end));
        } catch (NumberFormatException ignored) {
            return MISSING_MS;
        }
    }
}

package app.opendisplay.android.protocol;

import java.io.EOFException;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.nio.charset.StandardCharsets;
import java.util.Locale;
import java.util.Map;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

public final class LengthPrefixedProtocol {
    private static final Pattern STREAM_CONFIG_TYPE = Pattern.compile(
            "\\\"type\\\"\\s*:\\s*\\\"streamConfig\\\"");
    private static final Pattern PROTOCOL_VERSION_FIELD = Pattern.compile(
            "\\\"protocolVersion\\\"\\s*:\\s*(-?\\d+)");
    private static final Pattern MAX_FRAME_BYTES_FIELD = Pattern.compile(
            "\\\"maxFrameBytes\\\"\\s*:\\s*(-?\\d+)");
    public static final int LEGACY_MAX_FRAME_BYTES = 1 << 20;
    public static final int V2_DEFAULT_MAX_FRAME_BYTES = 8 << 20;
    public static final int ABSOLUTE_MAX_FRAME_BYTES = 16 << 20;
    public static final int MAX_FRAME_BYTES = LEGACY_MAX_FRAME_BYTES;
    public static final int NEGOTIATED_PROTOCOL_VERSION = 2;
    public static final String[] NEGOTIATED_CAPABILITIES = new String[] {
            "streamConfigAck",
            "decoderReady",
            "firstFrameRendered",
            "sessionEpoch",
            "configVersion",
            "frameSequence",
            "maxFrameBytes"
    };

    public enum FrameLengthFailure {
        INVALID_LENGTH,
        OVERSIZE,
        ABSOLUTE_LIMIT
    }

    public static final class FrameLengthException extends IOException {
        public final FrameLengthFailure failure;
        public final int frameBytes;
        public final int maximumBytes;

        FrameLengthException(
                FrameLengthFailure failure, int frameBytes, int maximumBytes) {
            super("invalid OpenDisplay frame length: " + frameBytes
                    + " reason=" + failure.name().toLowerCase(Locale.US)
                    + " maximum=" + maximumBytes);
            this.failure = failure;
            this.frameBytes = frameBytes;
            this.maximumBytes = maximumBytes;
        }
    }

    private LengthPrefixedProtocol() {}

    public static byte[] encode(byte[] payload) {
        ByteBuffer buffer = ByteBuffer.allocate(4 + payload.length).order(ByteOrder.BIG_ENDIAN);
        buffer.putInt(payload.length);
        buffer.put(payload);
        return buffer.array();
    }

    public static void write(OutputStream out, byte[] payload) throws IOException {
        out.write(encode(payload));
        out.flush();
    }

    public static byte[] read(InputStream in) throws IOException {
        return read(in, LEGACY_MAX_FRAME_BYTES);
    }

    public static byte[] read(InputStream in, int maximumBytes) throws IOException {
        byte[] header = readExact(in, 4);
        int length = ByteBuffer.wrap(header).order(ByteOrder.BIG_ENDIAN).getInt();
        int boundedMaximum = boundedFrameLimit(maximumBytes);
        if (length <= 0) {
            throw new FrameLengthException(
                    FrameLengthFailure.INVALID_LENGTH, length, boundedMaximum);
        }
        if (length > ABSOLUTE_MAX_FRAME_BYTES) {
            throw new FrameLengthException(
                    FrameLengthFailure.ABSOLUTE_LIMIT, length, boundedMaximum);
        }
        if (length > boundedMaximum) {
            throw new FrameLengthException(
                    FrameLengthFailure.OVERSIZE, length, boundedMaximum);
        }
        return readExact(in, length);
    }

    public static int boundedFrameLimit(int requestedBytes) {
        if (requestedBytes <= 0) {
            return LEGACY_MAX_FRAME_BYTES;
        }
        return Math.min(requestedBytes, ABSOLUTE_MAX_FRAME_BYTES);
    }

    public static int negotiatedV2FrameLimit(int requestedBytes) {
        return Math.min(V2_DEFAULT_MAX_FRAME_BYTES, boundedFrameLimit(requestedBytes));
    }

    public static int streamConfigFrameLimit(byte[] payload) {
        if (!isPureJsonControl(payload)) {
            return -1;
        }
        String json = new String(payload, StandardCharsets.UTF_8);
        if (!STREAM_CONFIG_TYPE.matcher(json).find()) {
            return -1;
        }
        int protocolVersion = integerField(json, PROTOCOL_VERSION_FIELD, 1);
        if (protocolVersion < NEGOTIATED_PROTOCOL_VERSION) {
            return LEGACY_MAX_FRAME_BYTES;
        }
        int requested = integerField(
                json, MAX_FRAME_BYTES_FIELD, V2_DEFAULT_MAX_FRAME_BYTES);
        return negotiatedV2FrameLimit(requested);
    }

    private static int integerField(String json, Pattern field, int fallback) {
        Matcher matcher = field.matcher(json);
        if (!matcher.find()) {
            return fallback;
        }
        try {
            return Integer.parseInt(matcher.group(1));
        } catch (NumberFormatException ignored) {
            return fallback;
        }
    }

    public static byte[] readExact(InputStream in, int length) throws IOException {
        byte[] data = new byte[length];
        int offset = 0;
        while (offset < length) {
            int n = in.read(data, offset, length - offset);
            if (n < 0) {
                throw new EOFException("stream ended after " + offset + " of " + length + " bytes");
            }
            offset += n;
        }
        return data;
    }

    public static boolean isPureJsonControl(byte[] payload) {
        if (payload.length == 0 || payload.length >= 32_768 || payload[0] != '{') {
            return false;
        }
        for (byte b : payload) {
            if (b == 0) {
                return false;
            }
        }
        return true;
    }

    public static byte[] jsonBytes(String json) {
        return json.getBytes(StandardCharsets.UTF_8);
    }

    public static String helloJson(int pixelsWide, int pixelsHigh, double scale,
                                   String device, String installId) {
        return helloJson(pixelsWide, pixelsHigh, scale, 60, 60,
                new String[] {"h264"}, "h264", device, 0, "wifi", device, installId);
    }

    public static String helloJson(int pixelsWide, int pixelsHigh, double scale,
                                   int refreshRate, int maxFps,
                                   String[] supportedCodecs, String preferredCodec,
                                   String deviceModel, int androidSdk, String transport,
                                   String device, String installId) {
        return String.format(Locale.US,
                "{\"type\":\"hello\",\"pixelsWide\":%d,\"pixelsHigh\":%d,\"scale\":%.3f,"
                        + "\"refreshRate\":%d,\"maxFps\":%d,\"supportedCodecs\":%s,"
                        + "\"preferredCodec\":\"%s\",\"deviceModel\":\"%s\",\"androidSdk\":%d,"
                        + "\"transport\":\"%s\",\"device\":\"%s\",\"id\":\"%s\","
                        + "\"protocolVersion\":%d,\"maxFrameBytes\":%d,"
                        + "\"capabilities\":%s}",
                pixelsWide, pixelsHigh, scale,
                sanitizeFps(refreshRate), sanitizeFps(maxFps),
                stringArrayJson(supportedCodecs),
                escape(preferredCodec),
                escape(deviceModel),
                Math.max(0, androidSdk),
                escape(transport),
                escape(device),
                escape(installId),
                NEGOTIATED_PROTOCOL_VERSION,
                V2_DEFAULT_MAX_FRAME_BYTES,
                stringArrayJson(NEGOTIATED_CAPABILITIES));
    }

    public static String touchJson(String phase, double x, double y, Double macClockMs) {
        String base = String.format(Locale.US,
                "{\"type\":\"touch\",\"phase\":\"%s\",\"x\":%.6f,\"y\":%.6f",
                escape(phase), clamp01(x), clamp01(y));
        if (macClockMs != null) {
            base += String.format(Locale.US, ",\"t\":%.3f", macClockMs);
        }
        return base + "}";
    }

    public static String pingJson(double nowMs) {
        return String.format(Locale.US, "{\"type\":\"ping\",\"t\":%.3f}", nowMs);
    }

    public static String pongJson(double receiverTimeMs, double macTimeMs) {
        return String.format(Locale.US, "{\"type\":\"pong\",\"t\":%.3f,\"mt\":%.3f}",
                receiverTimeMs, macTimeMs);
    }

    public static String keyframeRequestJson() {
        return "{\"type\":\"kf\"}";
    }

    public static String decoderResetRequestJson(boolean negotiatedV2) {
        if (!negotiatedV2) {
            return keyframeRequestJson();
        }
        return "{\"type\":\"kf\",\"reason\":\"decoderReset\","
                + "\"streamConfigRequired\":true}";
    }

    public static String goodbyeJson() {
        return "{\"type\":\"goodbye\"}";
    }

    public static String codecFailureJson(String codec, String message) {
        return String.format(Locale.US,
                "{\"type\":\"codecFailure\",\"codec\":\"%s\",\"message\":\"%s\"}",
                escape(codec), escape(message));
    }

    public static String streamConfigJson(String codec, int fps, int width, int height,
                                          int bitrate, String profile, String transport) {
        return String.format(Locale.US,
                "{\"type\":\"streamConfig\",\"codec\":\"%s\",\"fps\":%d,\"width\":%d,"
                        + "\"height\":%d,\"bitrate\":%d,\"profile\":\"%s\",\"transport\":\"%s\"}",
                escape(codec),
                sanitizeFps(fps),
                Math.max(1, width),
                Math.max(1, height),
                Math.max(0, bitrate),
                escape(profile),
                escape(transport));
    }

    public static String streamConfigAckJson(
            long sessionEpoch, long configVersion, boolean accepted,
            String codec, int fps, int width, int height, boolean surfaceValid) {
        return String.format(Locale.US,
                "{\"type\":\"streamConfigAck\",\"sessionEpoch\":%d,"
                        + "\"configVersion\":%d,\"accepted\":%s,\"codec\":\"%s\","
                        + "\"fps\":%d,\"width\":%d,\"height\":%d,"
                        + "\"surfaceValid\":%s}",
                Math.max(0, sessionEpoch), Math.max(0, configVersion), accepted,
                escape(codec), sanitizeFps(fps), Math.max(1, width), Math.max(1, height),
                surfaceValid);
    }

    public static String decoderReadyJson(
            long sessionEpoch, long configVersion, String codec, String decoderName,
            boolean hardwareAccelerated, boolean softwareOnly, boolean vendor,
            boolean lowLatencySupported, boolean lowLatencyEnabled,
            boolean configureSuccess, String fallbackReason) {
        return String.format(Locale.US,
                "{\"type\":\"decoderReady\",\"sessionEpoch\":%d,"
                        + "\"configVersion\":%d,\"codec\":\"%s\","
                        + "\"decoderName\":\"%s\",\"hardwareAccelerated\":%s,"
                        + "\"softwareOnly\":%s,\"vendor\":%s,"
                        + "\"lowLatencySupported\":%s,"
                        + "\"lowLatencyEnabled\":%s,\"configureSuccess\":%s,"
                        + "\"fallbackReason\":\"%s\"}",
                Math.max(0, sessionEpoch), Math.max(0, configVersion), escape(codec),
                escape(decoderName), hardwareAccelerated, softwareOnly, vendor,
                lowLatencySupported, lowLatencyEnabled, configureSuccess,
                escape(fallbackReason));
    }

    public static String firstFrameRenderedJson(
            long sessionEpoch, long configVersion, long frameSequence) {
        return String.format(Locale.US,
                "{\"type\":\"firstFrameRendered\",\"sessionEpoch\":%d,"
                        + "\"configVersion\":%d,\"frameSequence\":%d}",
                Math.max(0, sessionEpoch), Math.max(0, configVersion),
                Math.max(0, frameSequence));
    }

    public static String connectionStateJson(
            String state, String reason, long enteredAt, long generation,
            long sessionEpoch, long configVersion) {
        return String.format(Locale.US,
                "{\"type\":\"connectionState\",\"state\":\"%s\","
                        + "\"reason\":\"%s\",\"enteredAt\":%d,\"generation\":%d,"
                        + "\"sessionEpoch\":%d,\"configVersion\":%d}",
                escape(lowerCamel(state)), escape(reason), Math.max(0, enteredAt),
                Math.max(0, generation), Math.max(0, sessionEpoch),
                Math.max(0, configVersion));
    }

    public static String scrollJson(double dx, double dy) {
        return String.format(Locale.US, "{\"type\":\"scroll\",\"dx\":%.3f,\"dy\":%.3f}", dx, dy);
    }

    public static String statsJson(Map<String, Object> values) {
        StringBuilder out = new StringBuilder("{\"type\":\"stats\"");
        for (Map.Entry<String, Object> entry : values.entrySet()) {
            out.append(",\"").append(escape(entry.getKey())).append("\":");
            appendJsonValue(out, entry.getValue());
        }
        return out.append("}").toString();
    }

    private static void appendJsonValue(StringBuilder out, Object value) {
        if (value == null
                || (value instanceof Double && !Double.isFinite((Double) value))
                || (value instanceof Float && !Float.isFinite((Float) value))) {
            out.append("null");
        } else if (value instanceof Number || value instanceof Boolean) {
            out.append(value);
        } else if (value instanceof Map) {
            out.append("{");
            boolean first = true;
            for (Object rawEntry : ((Map<?, ?>) value).entrySet()) {
                Map.Entry<?, ?> entry = (Map.Entry<?, ?>) rawEntry;
                if (!first) {
                    out.append(",");
                }
                out.append("\"").append(escape(String.valueOf(entry.getKey())))
                        .append("\":");
                appendJsonValue(out, entry.getValue());
                first = false;
            }
            out.append("}");
        } else if (value instanceof Iterable) {
            out.append("[");
            boolean first = true;
            for (Object item : (Iterable<?>) value) {
                if (!first) {
                    out.append(",");
                }
                appendJsonValue(out, item);
                first = false;
            }
            out.append("]");
        } else {
            out.append("\"").append(escape(String.valueOf(value))).append("\"");
        }
    }

    public static double nowMs() {
        return System.currentTimeMillis();
    }

    private static double clamp01(double value) {
        return Math.max(0.0, Math.min(1.0, value));
    }

    private static String escape(String text) {
        if (text == null) {
            return "";
        }
        return text.replace("\\", "\\\\").replace("\"", "\\\"");
    }

    private static int sanitizeFps(int fps) {
        if (fps >= 110) return 120;
        if (fps >= 80) return 90;
        if (fps >= 45) return 60;
        return 30;
    }

    private static String stringArrayJson(String[] values) {
        StringBuilder out = new StringBuilder("[");
        if (values != null) {
            boolean first = true;
            for (String value : values) {
                if (value == null || value.length() == 0) {
                    continue;
                }
                if (!first) {
                    out.append(",");
                }
                out.append("\"").append(escape(value)).append("\"");
                first = false;
            }
        }
        return out.append("]").toString();
    }

    private static String lowerCamel(String value) {
        if (value == null || value.length() == 0) {
            return "";
        }
        StringBuilder result = new StringBuilder();
        boolean uppercaseNext = false;
        for (int i = 0; i < value.length(); i++) {
            char c = value.charAt(i);
            if (c == '_') {
                uppercaseNext = result.length() > 0;
            } else if (uppercaseNext) {
                result.append(Character.toUpperCase(c));
                uppercaseNext = false;
            } else {
                result.append(Character.toLowerCase(c));
            }
        }
        return result.toString();
    }
}

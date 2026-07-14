package app.opendisplay.android.protocol;

import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.util.Locale;

/** Fixed, network-byte-order metadata header used only after Android capability negotiation. */
public final class BinaryFrameHeaderV2 {
    public static final int MAGIC = 0x44575632; // "DWV2"
    public static final int VERSION = 2;
    public static final int HEADER_BYTES = 52;
    public static final int MAX_PAYLOAD_BYTES =
            LengthPrefixedProtocol.ABSOLUTE_MAX_FRAME_BYTES - HEADER_BYTES;

    public static final int FLAG_KEYFRAME = 1 << 0;
    public static final int FLAG_CODEC_CONFIG = 1 << 1;
    public static final int FLAG_HEVC = 1 << 2;
    public static final int FLAG_H264 = 1 << 3;
    private static final int KNOWN_FLAGS = FLAG_KEYFRAME | FLAG_CODEC_CONFIG
            | FLAG_HEVC | FLAG_H264;

    public enum Failure {
        NOT_BINARY,
        TRUNCATED_HEADER,
        UNKNOWN_VERSION,
        INVALID_HEADER_LENGTH,
        INVALID_FLAGS,
        INVALID_IDENTITY,
        INVALID_PAYLOAD_LENGTH,
        OVERSIZE_PAYLOAD
    }

    public static final class ParseException extends Exception {
        public final Failure failure;

        public ParseException(Failure failure, String detail) {
            super("invalid binary frame header v2: "
                    + failure.name().toLowerCase(Locale.US) + " " + detail);
            this.failure = failure;
        }
    }

    public static final class Parsed {
        public final byte[] frame;
        public final int flags;
        public final int payloadOffset;
        public final int payloadLength;
        public final long sessionEpoch;
        public final long configVersion;
        public final long frameSequence;
        public final long captureTimestampMs;
        public final long sendTimestampMs;

        Parsed(byte[] frame, int flags, int payloadOffset, int payloadLength,
               long sessionEpoch, long configVersion, long frameSequence,
               long captureTimestampMs, long sendTimestampMs) {
            this.frame = frame;
            this.flags = flags;
            this.payloadOffset = payloadOffset;
            this.payloadLength = payloadLength;
            this.sessionEpoch = sessionEpoch;
            this.configVersion = configVersion;
            this.frameSequence = frameSequence;
            this.captureTimestampMs = captureTimestampMs;
            this.sendTimestampMs = sendTimestampMs;
        }

        public boolean isKeyframe() {
            return (flags & FLAG_KEYFRAME) != 0;
        }

        public boolean hasCodecConfig() {
            return (flags & FLAG_CODEC_CONFIG) != 0;
        }

        public boolean isHevc() {
            return (flags & FLAG_HEVC) != 0;
        }

        public boolean isH264() {
            return (flags & FLAG_H264) != 0;
        }
    }

    private BinaryFrameHeaderV2() {}

    public static boolean looksLikeBinary(byte[] frame) {
        return frame != null && frame.length >= 4
                && frame[0] == 0x44 && frame[1] == 0x57
                && frame[2] == 0x56 && frame[3] == 0x32;
    }

    public static Parsed parse(byte[] frame) throws ParseException {
        if (!looksLikeBinary(frame)) {
            throw new ParseException(Failure.NOT_BINARY, "magic");
        }
        if (frame.length < HEADER_BYTES) {
            throw new ParseException(Failure.TRUNCATED_HEADER, "bytes=" + frame.length);
        }
        int version = Byte.toUnsignedInt(frame[4]);
        int flags = Byte.toUnsignedInt(frame[5]);
        int headerLength = readUInt16(frame, 6);
        if (version != VERSION) {
            throw new ParseException(Failure.UNKNOWN_VERSION, "version=" + version);
        }
        if (headerLength != HEADER_BYTES) {
            throw new ParseException(
                    Failure.INVALID_HEADER_LENGTH, "headerLength=" + headerLength);
        }
        validateFlags(flags);
        long sessionEpoch = readInt64(frame, 8);
        long configVersion = readInt64(frame, 16);
        long frameSequence = readInt64(frame, 24);
        long captureTimestampMs = readInt64(frame, 32);
        long sendTimestampMs = readInt64(frame, 40);
        int payloadLength = readInt32(frame, 48);
        if (sessionEpoch <= 0 || configVersion <= 0 || frameSequence <= 0
                || captureTimestampMs < 0 || sendTimestampMs < 0) {
            throw new ParseException(Failure.INVALID_IDENTITY, "non-positive identity");
        }
        if (payloadLength <= 0 || headerLength + (long) payloadLength != frame.length) {
            throw new ParseException(
                    Failure.INVALID_PAYLOAD_LENGTH,
                    "payloadLength=" + payloadLength + " frameBytes=" + frame.length);
        }
        if (payloadLength > MAX_PAYLOAD_BYTES) {
            throw new ParseException(Failure.OVERSIZE_PAYLOAD, "bytes=" + payloadLength);
        }
        return new Parsed(
                frame, flags, headerLength, payloadLength,
                sessionEpoch, configVersion, frameSequence,
                captureTimestampMs, sendTimestampMs);
    }

    /** Test/reference encoder; the production encoder is the matching Swift implementation. */
    public static byte[] encode(
            int flags, long sessionEpoch, long configVersion, long frameSequence,
            long captureTimestampMs, long sendTimestampMs, byte[] payload) {
        try {
            validateFlags(flags);
        } catch (ParseException error) {
            throw new IllegalArgumentException(error.getMessage(), error);
        }
        if (sessionEpoch <= 0 || configVersion <= 0 || frameSequence <= 0
                || captureTimestampMs < 0 || sendTimestampMs < 0) {
            throw new IllegalArgumentException("identity and timestamps must be non-negative");
        }
        if (payload == null || payload.length == 0
                || payload.length > MAX_PAYLOAD_BYTES) {
            throw new IllegalArgumentException("invalid payload length");
        }
        ByteBuffer frame = ByteBuffer.allocate(HEADER_BYTES + payload.length)
                .order(ByteOrder.BIG_ENDIAN);
        frame.putInt(MAGIC);
        frame.put((byte) VERSION);
        frame.put((byte) flags);
        frame.putShort((short) HEADER_BYTES);
        frame.putLong(sessionEpoch);
        frame.putLong(configVersion);
        frame.putLong(frameSequence);
        frame.putLong(captureTimestampMs);
        frame.putLong(sendTimestampMs);
        frame.putInt(payload.length);
        frame.put(payload);
        return frame.array();
    }

    private static void validateFlags(int flags) throws ParseException {
        boolean hevc = (flags & FLAG_HEVC) != 0;
        boolean h264 = (flags & FLAG_H264) != 0;
        if ((flags & ~KNOWN_FLAGS) != 0 || hevc == h264) {
            throw new ParseException(Failure.INVALID_FLAGS, "flags=" + flags);
        }
    }

    private static int readUInt16(byte[] bytes, int offset) {
        return (Byte.toUnsignedInt(bytes[offset]) << 8)
                | Byte.toUnsignedInt(bytes[offset + 1]);
    }

    private static int readInt32(byte[] bytes, int offset) {
        return (Byte.toUnsignedInt(bytes[offset]) << 24)
                | (Byte.toUnsignedInt(bytes[offset + 1]) << 16)
                | (Byte.toUnsignedInt(bytes[offset + 2]) << 8)
                | Byte.toUnsignedInt(bytes[offset + 3]);
    }

    private static long readInt64(byte[] bytes, int offset) {
        long value = 0;
        for (int index = 0; index < 8; index++) {
            value = (value << 8) | Byte.toUnsignedLong(bytes[offset + index]);
        }
        return value;
    }
}

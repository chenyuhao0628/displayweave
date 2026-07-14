package app.opendisplay.android.protocol;

import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;

public final class AnnexB {
    private static final byte[] START_CODE = new byte[] {0, 0, 0, 1};

    private AnnexB() {}

    public static final class NalSummary {
        public final byte[] source;
        public final int payloadOffset;
        public final int payloadLength;
        public final boolean hasNalUnits;
        public final boolean isKeyframe;
        public final int nalUnitCount;
        private final int vpsOffset;
        private final int vpsLength;
        private final int spsOffset;
        private final int spsLength;
        private final int ppsOffset;
        private final int ppsLength;

        NalSummary(byte[] source, int payloadOffset, int payloadLength,
                   boolean hasNalUnits, boolean isKeyframe, int nalUnitCount,
                   int vpsOffset, int vpsLength, int spsOffset, int spsLength,
                   int ppsOffset, int ppsLength) {
            this.source = source;
            this.payloadOffset = payloadOffset;
            this.payloadLength = payloadLength;
            this.hasNalUnits = hasNalUnits;
            this.isKeyframe = isKeyframe;
            this.nalUnitCount = nalUnitCount;
            this.vpsOffset = vpsOffset;
            this.vpsLength = vpsLength;
            this.spsOffset = spsOffset;
            this.spsLength = spsLength;
            this.ppsOffset = ppsOffset;
            this.ppsLength = ppsLength;
        }

        public boolean hasCodecConfig() {
            return vpsLength > 0 || spsLength > 0 || ppsLength > 0;
        }

        public byte[] copyVps() { return copy(vpsOffset, vpsLength); }
        public byte[] copySps() { return copy(spsOffset, spsLength); }
        public byte[] copyPps() { return copy(ppsOffset, ppsLength); }

        private byte[] copy(int offset, int length) {
            return length <= 0 ? null : Arrays.copyOfRange(source, offset, offset + length);
        }
    }

    public static byte[] stripTelemetryPrefix(byte[] payload) {
        int start = firstStartCode(payload);
        if (start <= 0) {
            return payload;
        }
        return Arrays.copyOfRange(payload, start, payload.length);
    }

    public static String telemetryPrefix(byte[] payload) {
        int start = firstStartCode(payload);
        if (start <= 0) {
            return null;
        }
        return new String(payload, 0, start, StandardCharsets.UTF_8);
    }

    public static int firstStartCode(byte[] payload) {
        return firstStartCode(payload, 0, payload == null ? 0 : payload.length);
    }

    public static int firstStartCode(byte[] payload, int offset, int length) {
        if (payload == null || offset < 0 || length < 0
                || offset + (long) length > payload.length) {
            return -1;
        }
        int end = offset + length;
        for (int i = offset; i + 4 <= end; i++) {
            if (payload[i] == 0 && payload[i + 1] == 0
                    && payload[i + 2] == 0 && payload[i + 3] == 1) {
                return i;
            }
        }
        return -1;
    }

    public static NalSummary scan(
            byte[] payload, int offset, int length, boolean hevc,
            int vpsType, int spsType, int ppsType, int keyframeType) {
        if (payload == null || offset < 0 || length <= 0
                || offset + (long) length > payload.length) {
            return new NalSummary(payload, Math.max(0, offset), Math.max(0, length),
                    false, false, 0, -1, 0, -1, 0, -1, 0);
        }
        int end = offset + length;
        int startCode = firstStartCode(payload, offset, length);
        int nalCount = 0;
        boolean keyframe = false;
        int vpsOffset = -1, vpsLength = 0;
        int spsOffset = -1, spsLength = 0;
        int ppsOffset = -1, ppsLength = 0;
        while (startCode >= 0) {
            int nalOffset = startCode + 4;
            int next = firstStartCode(payload, nalOffset, end - nalOffset);
            int nalEnd = next >= 0 ? next : end;
            int nalLength = nalEnd - nalOffset;
            if (nalLength > 0) {
                nalCount++;
                int type = hevc
                        ? (nalLength > 1 ? ((payload[nalOffset] >> 1) & 0x3F) : -1)
                        : (payload[nalOffset] & 0x1F);
                if (type == keyframeType || (hevc && type == 20)) {
                    keyframe = true;
                }
                if (type == vpsType && vpsLength == 0) {
                    vpsOffset = nalOffset;
                    vpsLength = nalLength;
                }
                if (type == spsType && spsLength == 0) {
                    spsOffset = nalOffset;
                    spsLength = nalLength;
                }
                if (type == ppsType && ppsLength == 0) {
                    ppsOffset = nalOffset;
                    ppsLength = nalLength;
                }
            }
            if (next < 0) {
                break;
            }
            startCode = next;
        }
        return new NalSummary(
                payload, offset, length, nalCount > 0, keyframe, nalCount,
                vpsOffset, vpsLength, spsOffset, spsLength, ppsOffset, ppsLength);
    }

    public static List<byte[]> nalUnits(byte[] annexBPayload) {
        byte[] payload = stripTelemetryPrefix(annexBPayload);
        List<byte[]> units = new ArrayList<>();
        int start = -1;
        for (int i = 0; i + 4 <= payload.length; ) {
            if (payload[i] == 0 && payload[i + 1] == 0
                    && payload[i + 2] == 0 && payload[i + 3] == 1) {
                if (start >= 0 && start < i) {
                    units.add(Arrays.copyOfRange(payload, start, i));
                }
                start = i + 4;
                i += 4;
            } else {
                i++;
            }
        }
        if (start >= 0 && start < payload.length) {
            units.add(Arrays.copyOfRange(payload, start, payload.length));
        }
        return units;
    }

    public static byte[] findNalUnit(byte[] payload, int nalType) {
        return findNalUnit(payload, nalType, false);
    }

    public static byte[] findNalUnit(byte[] payload, int nalType, boolean hevc) {
        for (byte[] unit : nalUnits(payload)) {
            if (unit.length > 0 && nalType(unit, hevc) == nalType) {
                return unit;
            }
        }
        return null;
    }

    private static int nalType(byte[] unit, boolean hevc) {
        return hevc ? ((unit[0] >> 1) & 0x3F) : (unit[0] & 0x1F);
    }

    public static byte[] withStartCode(byte[] nalu) {
        byte[] out = new byte[START_CODE.length + nalu.length];
        System.arraycopy(START_CODE, 0, out, 0, START_CODE.length);
        System.arraycopy(nalu, 0, out, START_CODE.length, nalu.length);
        return out;
    }
}

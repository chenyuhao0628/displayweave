package app.opendisplay.android;

import app.opendisplay.android.protocol.AnnexB;

public final class VideoFrameClassifier {
    private VideoFrameClassifier() {}

    public static boolean isImportant(byte[] wirePayload, VideoStreamConfig config) {
        if (wirePayload == null || config == null) {
            return false;
        }
        byte[] payload = AnnexB.stripTelemetryPrefix(wirePayload);
        for (byte[] unit : AnnexB.nalUnits(payload)) {
            if (unit.length == 0) {
                continue;
            }
            int type = nalType(unit, config.isHevc());
            if (type == config.vpsNalType()
                    || type == config.spsNalType()
                    || type == config.ppsNalType()
                    || type == config.keyframeNalType()
                    || (config.isHevc() && type == 20)) {
                return true;
            }
        }
        return false;
    }

    private static int nalType(byte[] unit, boolean hevc) {
        if (hevc) {
            return unit.length > 1 ? (unit[0] >> 1) & 0x3F : -1;
        }
        return unit[0] & 0x1F;
    }
}

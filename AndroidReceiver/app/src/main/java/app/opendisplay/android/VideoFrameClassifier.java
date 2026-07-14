package app.opendisplay.android;

import app.opendisplay.android.protocol.AnnexB;

public final class VideoFrameClassifier {
    private VideoFrameClassifier() {}

    public static boolean isImportant(byte[] wirePayload, VideoStreamConfig config) {
        if (wirePayload == null || config == null) {
            return false;
        }
        AnnexB.NalSummary summary = summary(wirePayload, config);
        return summary.hasCodecConfig() || summary.isKeyframe;
    }

    public static boolean isKeyframe(byte[] wirePayload, VideoStreamConfig config) {
        if (wirePayload == null || config == null) {
            return false;
        }
        return summary(wirePayload, config).isKeyframe;
    }

    private static AnnexB.NalSummary summary(
            byte[] wirePayload, VideoStreamConfig config) {
        int offset = AnnexB.firstStartCode(wirePayload);
        int safeOffset = offset >= 0 ? offset : 0;
        return AnnexB.scan(
                wirePayload, safeOffset, wirePayload.length - safeOffset,
                config.isHevc(), config.vpsNalType(), config.spsNalType(),
                config.ppsNalType(), config.keyframeNalType());
    }
}

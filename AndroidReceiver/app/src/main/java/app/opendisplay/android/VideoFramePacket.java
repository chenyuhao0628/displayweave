package app.opendisplay.android;

import app.opendisplay.android.protocol.AnnexB;
import app.opendisplay.android.protocol.BinaryFrameHeaderV2;

/** Owns one transport buffer and a zero-copy view of its Annex-B payload. */
public final class VideoFramePacket {
    public final byte[] bytes;
    public final int payloadOffset;
    public final int payloadLength;
    public final VideoFrameTelemetry telemetry;
    public final boolean binaryHeaderV2;
    public final boolean keyframe;
    public final boolean codecConfig;
    private final boolean binaryHevc;
    private AnnexB.NalSummary nalSummary;

    private VideoFramePacket(
            byte[] bytes, int payloadOffset, int payloadLength,
            VideoFrameTelemetry telemetry, boolean binaryHeaderV2,
            boolean keyframe, boolean codecConfig, boolean binaryHevc,
            AnnexB.NalSummary nalSummary) {
        this.bytes = bytes;
        this.payloadOffset = payloadOffset;
        this.payloadLength = payloadLength;
        this.telemetry = telemetry;
        this.binaryHeaderV2 = binaryHeaderV2;
        this.keyframe = keyframe;
        this.codecConfig = codecConfig;
        this.binaryHevc = binaryHevc;
        this.nalSummary = nalSummary;
    }

    public static VideoFramePacket parse(
            byte[] wirePayload, long receivedAndroidMs, VideoStreamConfig config)
            throws BinaryFrameHeaderV2.ParseException {
        if (BinaryFrameHeaderV2.looksLikeBinary(wirePayload)) {
            BinaryFrameHeaderV2.Parsed parsed = BinaryFrameHeaderV2.parse(wirePayload);
            return new VideoFramePacket(
                    wirePayload, parsed.payloadOffset, parsed.payloadLength,
                    VideoFrameTelemetry.fromBinaryHeader(parsed, receivedAndroidMs),
                    true, parsed.isKeyframe(), parsed.hasCodecConfig(),
                    parsed.isHevc(), null);
        }

        int offset = AnnexB.firstStartCode(wirePayload);
        int safeOffset = offset >= 0 ? offset : 0;
        int length = Math.max(0, wirePayload.length - safeOffset);
        AnnexB.NalSummary summary = scan(
                wirePayload, safeOffset, length, config);
        return new VideoFramePacket(
                wirePayload, safeOffset, length,
                VideoFrameTelemetry.fromWirePayload(wirePayload, receivedAndroidMs),
                false, summary.isKeyframe, summary.hasCodecConfig(),
                false, summary);
    }

    public boolean isImportant() {
        return keyframe || codecConfig;
    }

    public boolean codecMatches(VideoStreamConfig config) {
        return !binaryHeaderV2 || (config != null && config.isHevc() == binaryHevc);
    }

    public boolean hasAnnexBPayload() {
        return payloadLength >= 5
                && AnnexB.firstStartCode(bytes, payloadOffset, payloadLength) == payloadOffset;
    }

    public synchronized AnnexB.NalSummary nalSummary(VideoStreamConfig config) {
        if (nalSummary == null) {
            nalSummary = scan(bytes, payloadOffset, payloadLength, config);
        }
        return nalSummary;
    }

    private static AnnexB.NalSummary scan(
            byte[] bytes, int offset, int length, VideoStreamConfig config) {
        VideoStreamConfig safeConfig = config == null ? VideoStreamConfig.DEFAULT : config;
        return AnnexB.scan(
                bytes, offset, length, safeConfig.isHevc(),
                safeConfig.vpsNalType(), safeConfig.spsNalType(),
                safeConfig.ppsNalType(), safeConfig.keyframeNalType());
    }
}

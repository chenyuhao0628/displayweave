package app.opendisplay.android;

import app.opendisplay.android.protocol.AnnexB;
import app.opendisplay.android.protocol.BinaryFrameHeaderV2;

/** Owns one transport buffer and a zero-copy view of its Annex-B payload. */
public final class VideoFramePacket implements AutoCloseable {
    private FrameBufferPool.Lease lease;
    private long receivedMonotonicNanos = System.nanoTime();
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
        return parse(wirePayload, wirePayload.length, receivedAndroidMs, config);
    }

    public static VideoFramePacket parse(FrameBufferPool.Lease borrowed, long receivedAndroidMs,
                                        VideoStreamConfig config) throws BinaryFrameHeaderV2.ParseException {
        VideoFramePacket packet = parse(borrowed.bytes(), borrowed.length, receivedAndroidMs, config);
        packet.lease = borrowed.retain();
        return packet;
    }

    public VideoFramePacket retained() {
        VideoFramePacket copy = new VideoFramePacket(bytes, payloadOffset, payloadLength, telemetry,
                binaryHeaderV2, keyframe, codecConfig, binaryHevc, nalSummary);
        if (lease != null) copy.lease = lease.retain();
        copy.receivedMonotonicNanos = receivedMonotonicNanos;
        return copy;
    }

    @Override public void close() { if (lease != null) lease.close(); }

    private static VideoFramePacket parse(byte[] wirePayload, int wireLength,
            long receivedAndroidMs, VideoStreamConfig config) throws BinaryFrameHeaderV2.ParseException {
        if (wireLength >= 4 && BinaryFrameHeaderV2.looksLikeBinary(wirePayload)) {
            BinaryFrameHeaderV2.Parsed parsed = BinaryFrameHeaderV2.parse(wirePayload, wireLength);
            return new VideoFramePacket(
                    wirePayload, parsed.payloadOffset, parsed.payloadLength,
                    VideoFrameTelemetry.fromBinaryHeader(parsed, receivedAndroidMs),
                    true, parsed.isKeyframe(), parsed.hasCodecConfig(),
                    parsed.isHevc(), null);
        }

        int offset = AnnexB.firstStartCode(wirePayload, 0, wireLength);
        int safeOffset = offset >= 0 ? offset : 0;
        int length = Math.max(0, wireLength - safeOffset);
        AnnexB.NalSummary summary = scan(
                wirePayload, safeOffset, length, config);
        return new VideoFramePacket(
                wirePayload, safeOffset, length,
                VideoFrameTelemetry.fromWirePayload(wirePayload, wireLength, receivedAndroidMs),
                false, summary.isKeyframe, summary.hasCodecConfig(),
                false, summary);
    }

    boolean queueDeadlineExpired() {
        return FrameQueuePolicy.expired(receivedMonotonicNanos, System.nanoTime());
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

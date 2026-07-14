package app.opendisplay.android;

public enum AndroidDropReason {
    LATEST_SLOT_REPLACED("latestSlotReplaced", true),
    IMPORTANT_FRAME_PROTECTED("importantFrameProtected", true),
    DECODER_INPUT_UNAVAILABLE("decoderInputUnavailable", true),
    DECODER_INPUT_OVERSIZE("decoderInputOversize", false),
    DECODER_EXCEPTION("decoderException", false),
    SURFACE_UNAVAILABLE("surfaceUnavailable", false),
    STALE_CONNECTION_GENERATION("staleConnectionGeneration", false),
    STALE_SESSION_EPOCH("staleSessionEpoch", false),
    STALE_CONFIG_VERSION("staleConfigVersion", false),
    INVALID_FRAME_LENGTH("invalidFrameLength", false),
    MALFORMED_ANNEX_B("malformedAnnexB", false),
    CODEC_RECONFIGURE_DROP("codecReconfigureDrop", false),
    TRANSPORT_READ_FAILURE("transportReadFailure", false),
    TRANSPORT_WRITE_FAILURE("transportWriteFailure", false),
    FRAME_AGE_EXPIRED("frameAgeExpired", true);

    public final String key;
    public final boolean congestionRelevant;

    AndroidDropReason(String key, boolean congestionRelevant) {
        this.key = key;
        this.congestionRelevant = congestionRelevant;
    }
}

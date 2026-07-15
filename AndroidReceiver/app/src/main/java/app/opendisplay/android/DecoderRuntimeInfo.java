package app.opendisplay.android;

public final class DecoderRuntimeInfo {
    public final String codec;
    public final String decoderName;
    public final boolean hardwareAccelerated;
    public final boolean softwareOnly;
    public final boolean vendor;
    public final boolean lowLatencySupported;
    public final boolean lowLatencyEnabled;
    public final boolean configureSuccess;
    public final int selectedDecoderMaxFps;
    public final String fallbackReason;

    DecoderRuntimeInfo(String codec, String decoderName,
                       boolean hardwareAccelerated, boolean softwareOnly, boolean vendor,
                       boolean lowLatencySupported, boolean lowLatencyEnabled,
                       boolean configureSuccess, int selectedDecoderMaxFps,
                       String fallbackReason) {
        this.codec = codec;
        this.decoderName = decoderName;
        this.hardwareAccelerated = hardwareAccelerated;
        this.softwareOnly = softwareOnly;
        this.vendor = vendor;
        this.lowLatencySupported = lowLatencySupported;
        this.lowLatencyEnabled = lowLatencyEnabled;
        this.configureSuccess = configureSuccess;
        this.selectedDecoderMaxFps = Math.max(30, selectedDecoderMaxFps);
        this.fallbackReason = fallbackReason == null ? "" : fallbackReason;
    }
}

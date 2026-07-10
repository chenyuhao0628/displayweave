package app.opendisplay.android;

public final class DisplaySpec {
    public final int pixelsWide;
    public final int pixelsHigh;
    public final double scale;
    public final int refreshRate;
    public final int maxFps;
    public final String[] supportedCodecs;
    public final String preferredCodec;
    public final String deviceModel;
    public final int androidSdk;
    public final String transport;

    public DisplaySpec(int pixelsWide, int pixelsHigh, double scale) {
        this(pixelsWide, pixelsHigh, scale, 60, 60,
                new String[] {"h264"}, "h264", "Android Tablet", 0, "wifi");
    }

    public DisplaySpec(int pixelsWide, int pixelsHigh, double scale,
                       int refreshRate, int maxFps,
                       String[] supportedCodecs, String preferredCodec,
                       String deviceModel, int androidSdk, String transport) {
        this.pixelsWide = pixelsWide;
        this.pixelsHigh = pixelsHigh;
        this.scale = scale;
        this.refreshRate = refreshRate;
        this.maxFps = maxFps;
        this.supportedCodecs = supportedCodecs == null || supportedCodecs.length == 0
                ? new String[] {"h264"}
                : supportedCodecs.clone();
        this.preferredCodec = preferredCodec == null || preferredCodec.length() == 0
                ? "h264"
                : preferredCodec;
        this.deviceModel = deviceModel == null || deviceModel.length() == 0
                ? "Android Tablet"
                : deviceModel;
        this.androidSdk = androidSdk;
        this.transport = transport == null || transport.length() == 0 ? "wifi" : transport;
    }
}

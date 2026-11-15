package app.opendisplay.android;

import java.util.Arrays;
import java.util.Objects;

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
    public final Integer millimetersWide;
    public final Integer millimetersHigh;

    public DisplaySpec(int pixelsWide, int pixelsHigh, double scale) {
        this(pixelsWide, pixelsHigh, scale, 60, 60,
                new String[] {"h264"}, "h264", "Android Tablet", 0, "wifi", null, null);
    }

    public DisplaySpec(int pixelsWide, int pixelsHigh, double scale,
                       int refreshRate, int maxFps,
                       String[] supportedCodecs, String preferredCodec,
                       String deviceModel, int androidSdk, String transport) {
        this(pixelsWide, pixelsHigh, scale, refreshRate, maxFps,
                supportedCodecs, preferredCodec, deviceModel, androidSdk, transport,
                null, null);
    }

    public DisplaySpec(int pixelsWide, int pixelsHigh, double scale,
                       int refreshRate, int maxFps,
                       String[] supportedCodecs, String preferredCodec,
                       String deviceModel, int androidSdk, String transport,
                       Integer millimetersWide, Integer millimetersHigh) {
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
        this.millimetersWide = millimetersWide;
        this.millimetersHigh = millimetersHigh;
    }

    public boolean sameDisplayConfiguration(DisplaySpec other) {
        if (other == null) {
            return false;
        }
        return pixelsWide == other.pixelsWide
                && pixelsHigh == other.pixelsHigh
                && Math.abs(scale - other.scale) < 0.001
                && refreshRate == other.refreshRate
                && maxFps == other.maxFps
                && Objects.equals(preferredCodec, other.preferredCodec)
                && Arrays.equals(supportedCodecs, other.supportedCodecs)
                && Objects.equals(millimetersWide, other.millimetersWide)
                && Objects.equals(millimetersHigh, other.millimetersHigh);
    }
}

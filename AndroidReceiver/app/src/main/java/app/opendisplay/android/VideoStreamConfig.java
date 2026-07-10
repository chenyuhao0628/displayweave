package app.opendisplay.android;

import android.media.MediaFormat;

import java.util.Locale;

public final class VideoStreamConfig {
    public static final VideoStreamConfig DEFAULT =
            new VideoStreamConfig("h264", MediaFormat.MIMETYPE_VIDEO_AVC, 60, 0, 0, 0);

    public final String codec;
    public final String mimeType;
    public final int fps;
    public final int width;
    public final int height;
    public final int bitrate;

    private VideoStreamConfig(String codec, String mimeType, int fps, int width, int height, int bitrate) {
        this.codec = codec;
        this.mimeType = mimeType;
        this.fps = fps;
        this.width = Math.max(0, width);
        this.height = Math.max(0, height);
        this.bitrate = Math.max(0, bitrate);
    }

    public static VideoStreamConfig from(String codecName, int fps, int width, int height, int bitrate) {
        String normalized = codecName == null ? "h264" : codecName.toLowerCase(Locale.US);
        if (!"hevc".equals(normalized) && !"h264".equals(normalized)) {
            normalized = "h264";
        }
        String mimeType = "hevc".equals(normalized)
                ? MediaFormat.MIMETYPE_VIDEO_HEVC
                : MediaFormat.MIMETYPE_VIDEO_AVC;
        return new VideoStreamConfig(normalized, mimeType, sanitizeFps(fps), width, height, bitrate);
    }

    public boolean isHevc() {
        return "hevc".equals(codec);
    }

    public int vpsNalType() {
        return isHevc() ? 32 : -1;
    }

    public int spsNalType() {
        return isHevc() ? 33 : 7;
    }

    public int ppsNalType() {
        return isHevc() ? 34 : 8;
    }

    public int keyframeNalType() {
        return isHevc() ? 19 : 5;
    }

    private static int sanitizeFps(int fps) {
        if (fps >= 110) return 120;
        if (fps >= 80) return 90;
        if (fps >= 45) return 60;
        return 30;
    }
}

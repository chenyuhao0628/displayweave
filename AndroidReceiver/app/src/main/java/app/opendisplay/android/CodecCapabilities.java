package app.opendisplay.android;

import android.media.MediaCodecInfo;
import android.media.MediaCodecList;
import android.media.MediaFormat;

import java.util.ArrayList;
import java.util.List;

public final class CodecCapabilities {
    private CodecCapabilities() {}

    public static String[] supportedVideoCodecs() {
        List<String> codecs = new ArrayList<>();
        if (hasUsableHardwareDecoder(MediaFormat.MIMETYPE_VIDEO_HEVC)) {
            codecs.add("hevc");
        }
        if (hasDecoder(MediaFormat.MIMETYPE_VIDEO_AVC)) {
            codecs.add("h264");
        }
        if (codecs.isEmpty()) {
            codecs.add("h264");
        }
        return codecs.toArray(new String[0]);
    }

    public static String preferredVideoCodec() {
        return hasUsableHardwareDecoder(MediaFormat.MIMETYPE_VIDEO_HEVC) ? "hevc" : "h264";
    }

    /**
     * Caps the display refresh rate by the preferred hardware decoder's
     * advertised size/rate performance. Screen Hz alone is not a video
     * decoding guarantee.
     */
    public static int maxSupportedFps(int width, int height, int displayMaxFps) {
        String mimeType = "hevc".equals(preferredVideoCodec())
                ? MediaFormat.MIMETYPE_VIDEO_HEVC : MediaFormat.MIMETYPE_VIDEO_AVC;
        int displayCap = sanitizeFps(displayMaxFps);
        int[] candidates = new int[] {120, 90, 60, 30};
        try {
            for (MediaCodecInfo info :
                    new MediaCodecList(MediaCodecList.ALL_CODECS).getCodecInfos()) {
                if (info.isEncoder() || !supportsType(info, mimeType)) {
                    continue;
                }
                String name = info.getName().toLowerCase(java.util.Locale.US);
                if (isSoftwareDecoderName(name)
                        || (MediaFormat.MIMETYPE_VIDEO_HEVC.equals(mimeType)
                        && isKnownBrokenHevcName(name))) {
                    continue;
                }
                MediaCodecInfo.VideoCapabilities video = info
                        .getCapabilitiesForType(mimeType).getVideoCapabilities();
                for (int fps : candidates) {
                    if (fps <= displayCap && supportsPerformance(video, width, height, fps)) {
                        return fps;
                    }
                }
            }
        } catch (RuntimeException ignored) {
        }
        return Math.min(displayCap, 60);
    }

    private static boolean supportsPerformance(
            MediaCodecInfo.VideoCapabilities video, int width, int height, int fps) {
        if (video == null || width <= 0 || height <= 0) {
            return false;
        }
        try {
            List<MediaCodecInfo.VideoCapabilities.PerformancePoint> points =
                    android.os.Build.VERSION.SDK_INT >= 29
                            ? video.getSupportedPerformancePoints() : null;
            if (points != null && !points.isEmpty()) {
                MediaCodecInfo.VideoCapabilities.PerformancePoint requested =
                        new MediaCodecInfo.VideoCapabilities.PerformancePoint(width, height, fps);
                for (MediaCodecInfo.VideoCapabilities.PerformancePoint point : points) {
                    if (point.covers(requested)) {
                        return true;
                    }
                }
                return false;
            }
            return video.areSizeAndRateSupported(width, height, fps);
        } catch (RuntimeException ignored) {
            return false;
        }
    }

    static int sanitizeFps(int fps) {
        if (fps >= 110) return 120;
        if (fps >= 80) return 90;
        if (fps >= 45) return 60;
        return 30;
    }

    private static boolean hasUsableHardwareDecoder(String mimeType) {
        try {
            for (MediaCodecInfo info : new MediaCodecList(MediaCodecList.ALL_CODECS).getCodecInfos()) {
                if (info.isEncoder() || !supportsType(info, mimeType)) {
                    continue;
                }
                String name = info.getName().toLowerCase(java.util.Locale.US);
                if (!isSoftwareDecoderName(name) && !isKnownBrokenHevcName(name)) {
                    return true;
                }
            }
        } catch (RuntimeException ignored) {
        }
        return false;
    }

    private static boolean hasDecoder(String mimeType) {
        try {
            for (MediaCodecInfo info : new MediaCodecList(MediaCodecList.ALL_CODECS).getCodecInfos()) {
                if (!info.isEncoder() && supportsType(info, mimeType)) {
                    return true;
                }
            }
        } catch (RuntimeException ignored) {
        }
        return MediaFormat.MIMETYPE_VIDEO_AVC.equals(mimeType);
    }

    private static boolean supportsType(MediaCodecInfo info, String mimeType) {
        for (String type : info.getSupportedTypes()) {
            if (type.equalsIgnoreCase(mimeType)) {
                return true;
            }
        }
        return false;
    }

    static boolean isSoftwareDecoderName(String name) {
        return name.startsWith("c2.android.") || name.startsWith("omx.google.");
    }

    static boolean isKnownBrokenHevcName(String name) {
        return name.startsWith("omx.sprd.") || name.startsWith("c2.sprd.");
    }
}

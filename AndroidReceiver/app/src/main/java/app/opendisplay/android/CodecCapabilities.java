package app.opendisplay.android;

import android.media.MediaCodecInfo;
import android.media.MediaCodecList;
import android.media.MediaFormat;

import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

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
        return maxSupportedFps(
                width, height, displayMaxFps, DecoderLowLatencyMode.AUTO);
    }

    public static int maxSupportedFps(
            int width, int height, int displayMaxFps,
            DecoderLowLatencyMode lowLatencyMode) {
        boolean prefersHevc = "hevc".equals(preferredVideoCodec());
        String mimeType = prefersHevc
                ? MediaFormat.MIMETYPE_VIDEO_HEVC : MediaFormat.MIMETYPE_VIDEO_AVC;
        int displayCap = sanitizeFps(displayMaxFps);
        int preferredCap = selectedDecoderMaxFps(
                mimeType, width, height, displayCap, lowLatencyMode);
        if (!prefersHevc) {
            return preferredCap;
        }
        // HEVC can fall back to H.264 without a new Hello exchange. Advertise
        // a rate that remains valid for the selected candidate on both paths.
        int h264FallbackCap = selectedDecoderMaxFps(
                MediaFormat.MIMETYPE_VIDEO_AVC, width, height, displayCap,
                lowLatencyMode);
        return Math.min(preferredCap, h264FallbackCap);
    }

    private static int selectedDecoderMaxFps(
            String mimeType, int width, int height, int displayCap,
            DecoderLowLatencyMode lowLatencyMode) {
        int[] candidates = new int[] {120, 90, 60, 30};
        List<DecoderSelectionPolicy.Candidate> selectionCandidates = new ArrayList<>();
        Map<String, Integer> capsByName = new LinkedHashMap<>();
        try {
            for (MediaCodecInfo info :
                    new MediaCodecList(MediaCodecList.ALL_CODECS).getCodecInfos()) {
                if (info.isEncoder() || !supportsType(info, mimeType)) {
                    continue;
                }
                String name = info.getName().toLowerCase(java.util.Locale.US);
                if (MediaFormat.MIMETYPE_VIDEO_HEVC.equals(mimeType)
                        && isKnownBrokenHevcName(name)) {
                    continue;
                }
                boolean softwareOnly = isSoftwareDecoderName(name);
                boolean hardwareAccelerated = !softwareOnly;
                boolean vendor = !softwareOnly;
                if (android.os.Build.VERSION.SDK_INT >= 29) {
                    hardwareAccelerated = info.isHardwareAccelerated();
                    softwareOnly = info.isSoftwareOnly();
                    vendor = info.isVendor();
                }
                boolean lowLatencySupported = false;
                if (android.os.Build.VERSION.SDK_INT >= 30) {
                    lowLatencySupported = info.getCapabilitiesForType(mimeType)
                            .isFeatureSupported(
                                    MediaCodecInfo.CodecCapabilities.FEATURE_LowLatency);
                }
                selectionCandidates.add(new DecoderSelectionPolicy.Candidate(
                        info.getName(), hardwareAccelerated, softwareOnly, vendor,
                        lowLatencySupported));
                MediaCodecInfo.VideoCapabilities video = info
                        .getCapabilitiesForType(mimeType).getVideoCapabilities();
                int supportedCap = Math.min(displayCap, 30);
                for (int fps : candidates) {
                    if (fps <= displayCap && supportsPerformance(video, width, height, fps)) {
                        supportedCap = fps;
                        break;
                    }
                }
                capsByName.put(info.getName(), supportedCap);
            }
            List<DecoderSelectionPolicy.Attempt> attempts =
                    DecoderSelectionPolicy.attempts(
                            selectionCandidates, lowLatencyMode);
            if (!attempts.isEmpty()) {
                Integer selectedCap = capsByName.get(attempts.get(0).decoderName);
                if (selectedCap != null) {
                    return selectedCap;
                }
            }
        } catch (RuntimeException ignored) {
        }
        return Math.min(displayCap, 60);
    }

    static int decoderMaxFps(
            String mimeType, String decoderName,
            int width, int height, int requestedFps) {
        int cap = sanitizeFps(requestedFps);
        if (decoderName == null || decoderName.length() == 0) {
            return Math.min(cap, 60);
        }
        try {
            for (MediaCodecInfo info :
                    new MediaCodecList(MediaCodecList.ALL_CODECS).getCodecInfos()) {
                if (info.isEncoder() || !info.getName().equals(decoderName)
                        || !supportsType(info, mimeType)) {
                    continue;
                }
                MediaCodecInfo.VideoCapabilities video = info
                        .getCapabilitiesForType(mimeType).getVideoCapabilities();
                for (int fps : new int[] {120, 90, 60, 30}) {
                    if (fps <= cap && supportsPerformance(video, width, height, fps)) {
                        return fps;
                    }
                }
                return 30;
            }
        } catch (RuntimeException ignored) {
        }
        return Math.min(cap, 60);
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

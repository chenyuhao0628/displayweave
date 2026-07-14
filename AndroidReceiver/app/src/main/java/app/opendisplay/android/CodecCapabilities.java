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

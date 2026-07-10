package app.opendisplay.android;

import java.util.Locale;

public final class CodecFallbackStatus {
    private CodecFallbackStatus() {}

    public static String messageForCodecFailure(String codec) {
        String normalized = codec == null ? "" : codec.toLowerCase(Locale.US);
        if ("hevc".equals(normalized)) {
            return "HEVC 不可用，已请求回退 H.264";
        }
        return null;
    }
}

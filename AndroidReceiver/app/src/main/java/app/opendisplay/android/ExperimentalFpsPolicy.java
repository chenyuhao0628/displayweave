package app.opendisplay.android;

/** Explicit opt-in envelope, not a measured throughput claim. */
final class ExperimentalFpsPolicy {
    static boolean allowsNative60(boolean enabled, int width, int height, int fps) {
        return enabled && width > 0 && height > 0 && fps > 0 && fps <= 60
                && Math.max(width, height) <= 2400 && Math.min(width, height) <= 1080;
    }
}

package app.opendisplay.android;

final class DecoderStallRecoveryPolicy {
    static final long RECENT_VIDEO_WINDOW_MS = 1_500;
    static final long RENDER_STALL_MS = 2_000;
    static final long RECOVERY_COOLDOWN_MS = 5_000;

    private DecoderStallRecoveryPolicy() {
    }

    static boolean shouldRecover(long nowMs, long lastVideoReceivedMs,
                                 long lastFrameRenderedMs, long lastRecoveryMs) {
        return lastVideoReceivedMs > 0
                && nowMs - lastVideoReceivedMs <= RECENT_VIDEO_WINDOW_MS
                && nowMs - lastFrameRenderedMs >= RENDER_STALL_MS
                && (lastRecoveryMs == 0 || nowMs - lastRecoveryMs >= RECOVERY_COOLDOWN_MS);
    }

    static boolean requiresFreshStreamConfigForStall(boolean negotiatedV2) {
        return negotiatedV2;
    }

    static boolean requiresFreshStreamConfigForCodecFailure(
            boolean negotiatedV2, String codec) {
        return negotiatedV2 || "hevc".equalsIgnoreCase(codec);
    }

    static boolean shouldRecreateDecoderInPlace(boolean requireFreshConfig) {
        return !requireFreshConfig;
    }
}

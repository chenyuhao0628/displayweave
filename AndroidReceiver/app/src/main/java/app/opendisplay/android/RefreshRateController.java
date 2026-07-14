package app.opendisplay.android;

public final class RefreshRateController {
    private RefreshRateController() {}

    public static float chooseRefreshRate(int requestedFps, float[] supportedRates, float fallback) {
        if (supportedRates == null || supportedRates.length == 0) {
            return fallback;
        }
        float requested = sanitizeFps(requestedFps);
        float bestAtOrAbove = Float.MAX_VALUE;
        float bestBelow = -1f;
        for (float rate : supportedRates) {
            if (!Float.isFinite(rate) || rate <= 0f) {
                continue;
            }
            if (rate >= requested && rate < bestAtOrAbove) {
                bestAtOrAbove = rate;
            } else if (rate < requested && rate > bestBelow) {
                bestBelow = rate;
            }
        }
        if (bestAtOrAbove != Float.MAX_VALUE) {
            return bestAtOrAbove;
        }
        return bestBelow > 0f ? bestBelow : fallback;
    }

    public static int sanitizeFps(int fps) {
        if (fps >= 110) return 120;
        if (fps >= 80) return 90;
        if (fps >= 45) return 60;
        return 30;
    }
}

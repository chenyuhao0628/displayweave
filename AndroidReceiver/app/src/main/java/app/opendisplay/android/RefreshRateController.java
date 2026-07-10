package app.opendisplay.android;

public final class RefreshRateController {
    private RefreshRateController() {}

    public static float chooseRefreshRate(int requestedFps, float[] supportedRates, float fallback) {
        if (supportedRates == null || supportedRates.length == 0) {
            return fallback;
        }
        float requested = sanitizeFps(requestedFps);
        float best = fallback;
        float bestDistance = Float.MAX_VALUE;
        for (float rate : supportedRates) {
            float distance = Math.abs(rate - requested);
            if (distance < bestDistance) {
                best = rate;
                bestDistance = distance;
            }
        }
        return best;
    }

    public static int sanitizeFps(int fps) {
        if (fps >= 110) return 120;
        if (fps >= 80) return 90;
        if (fps >= 45) return 60;
        return 30;
    }
}

package app.opendisplay.android;

public final class WifiLowLatencyLifecycle {
    public interface LockAdapter {
        boolean acquire();
        boolean release();
        boolean isHeld();
    }

    public static final class Snapshot {
        public final String mode;
        public final boolean requested;
        public final boolean acquired;
        public final boolean active;
        public final String releaseReason;

        Snapshot(String mode, boolean requested, boolean acquired,
                 boolean active, String releaseReason) {
            this.mode = mode;
            this.requested = requested;
            this.acquired = acquired;
            this.active = active;
            this.releaseReason = releaseReason;
        }
    }

    private final int sdkInt;
    private final LockAdapter lock;
    private WifiLowLatencyMode mode = WifiLowLatencyMode.AUTO;
    private boolean requested;
    private boolean acquired;
    private boolean active;
    private String releaseReason = "notStreaming";

    public WifiLowLatencyLifecycle(int sdkInt, LockAdapter lock) {
        this.sdkInt = sdkInt;
        this.lock = lock;
    }

    public synchronized void update(
            WifiLowLatencyMode nextMode,
            boolean foreground,
            boolean streaming,
            boolean surfaceValid,
            String transport) {
        mode = nextMode == null ? WifiLowLatencyMode.AUTO : nextMode;
        requested = mode.requestsLowLatency();
        String ineligibleReason = ineligibleReason(
                mode, sdkInt, foreground, streaming, surfaceValid, transport);
        if (ineligibleReason == null) {
            if (lock == null) {
                acquired = false;
                active = false;
                releaseReason = "wifiServiceUnavailable";
                return;
            }
            if (!safeIsHeld()) {
                acquired = safeAcquire();
            } else {
                acquired = true;
            }
            active = safeIsHeld();
            if (active) {
                releaseReason = "";
            } else if (releaseReason.length() == 0) {
                releaseReason = "acquireFailed";
            }
            return;
        }

        if (lock != null && safeIsHeld() && !safeRelease()) {
            acquired = safeIsHeld();
            active = acquired;
            releaseReason = "releaseFailed:" + ineligibleReason;
            return;
        }
        acquired = false;
        active = false;
        releaseReason = ineligibleReason;
    }

    public synchronized void shutdown(String reason) {
        if (lock != null && safeIsHeld() && !safeRelease()) {
            acquired = safeIsHeld();
            active = acquired;
            releaseReason = "releaseFailed:" + safeReason(reason, "shutdown");
            return;
        }
        acquired = false;
        active = false;
        releaseReason = safeReason(reason, "shutdown");
    }

    public synchronized Snapshot snapshot() {
        return new Snapshot(mode.key, requested, acquired, active, releaseReason);
    }

    private boolean safeAcquire() {
        try {
            boolean result = lock.acquire();
            if (!result) {
                releaseReason = "acquireFailed";
            }
            return result;
        } catch (RuntimeException error) {
            releaseReason = "acquireFailed:" + error.getClass().getSimpleName();
            return false;
        }
    }

    private boolean safeRelease() {
        try {
            return lock.release();
        } catch (RuntimeException error) {
            return false;
        }
    }

    private boolean safeIsHeld() {
        try {
            return lock.isHeld();
        } catch (RuntimeException error) {
            return false;
        }
    }

    private static String ineligibleReason(
            WifiLowLatencyMode mode, int sdkInt, boolean foreground,
            boolean streaming, boolean surfaceValid, String transport) {
        if (!mode.requestsLowLatency()) {
            return "disabledByUser";
        }
        if (sdkInt < 29) {
            return "unsupportedApi";
        }
        if (!foreground) {
            return "appBackground";
        }
        if (!surfaceValid) {
            return "surfaceUnavailable";
        }
        if (!streaming) {
            return "notStreaming";
        }
        if (!"wifi".equalsIgnoreCase(transport == null ? "" : transport.trim())) {
            return "transportNotWifi";
        }
        return null;
    }

    private static String safeReason(String reason, String fallback) {
        return reason == null || reason.length() == 0 ? fallback : reason;
    }
}

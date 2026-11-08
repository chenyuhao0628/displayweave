package app.opendisplay.android;

final class ReceiverLifecycleCoordinator {
    interface Actions {
        boolean start();
        void stop();
    }

    private final Actions actions;
    private boolean resumed;
    private boolean surfaceAvailable;
    private boolean sessionConnected;
    private boolean running;

    ReceiverLifecycleCoordinator(Actions actions) {
        this.actions = actions;
    }

    void onResume() {
        resumed = true;
        ensureStarted();
    }

    void onPause() {
        resumed = false;
        if (!sessionConnected) {
            stopIfRunning();
        }
    }

    void onSurfaceCreated() {
        surfaceAvailable = true;
        ensureStarted();
    }

    void onSurfaceDestroyed() {
        surfaceAvailable = false;
        if (!sessionConnected) {
            stopIfRunning();
        }
    }

    void onConnectionChanged(boolean connected) {
        sessionConnected = connected;
        if (!connected && (!resumed || !surfaceAvailable)) {
            stopIfRunning();
        }
    }

    void onDestroy() {
        resumed = false;
        surfaceAvailable = false;
        sessionConnected = false;
        stopIfRunning();
    }

    /** Security settings stop first, then reevaluate after persistence succeeds. */
    void stopForSettings() {
        sessionConnected = false;
        stopIfRunning();
    }

    void reevaluate() {
        if (!resumed || !surfaceAvailable) {
            if (!sessionConnected) {
                stopIfRunning();
            }
            return;
        }
        ensureStarted();
    }

    private void ensureStarted() {
        if (!resumed || !surfaceAvailable || running) {
            return;
        }
        running = actions.start();
    }

    private void stopIfRunning() {
        if (!running) {
            return;
        }
        running = false;
        actions.stop();
    }
}

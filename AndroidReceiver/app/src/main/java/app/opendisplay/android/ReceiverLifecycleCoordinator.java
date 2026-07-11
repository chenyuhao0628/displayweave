package app.opendisplay.android;

final class ReceiverLifecycleCoordinator {
    interface Actions {
        boolean start();
        void stop();
    }

    private final Actions actions;
    private boolean resumed;
    private boolean surfaceAvailable;
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
    }

    void onSurfaceCreated() {
        surfaceAvailable = true;
        ensureStarted();
    }

    void onSurfaceDestroyed() {
        surfaceAvailable = false;
        stopIfRunning();
    }

    void onDestroy() {
        resumed = false;
        surfaceAvailable = false;
        stopIfRunning();
    }

    void reevaluate() {
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

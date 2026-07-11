package app.opendisplay.android;

public final class ReceiverLifecycleSelfTest {
    private static final class RecordingActions
            implements ReceiverLifecycleCoordinator.Actions {
        int starts;
        int startAttempts;
        int stops;
        boolean allowStart = true;

        @Override
        public boolean start() {
            startAttempts++;
            if (allowStart) {
                starts++;
            }
            return allowStart;
        }

        @Override
        public void stop() {
            stops++;
        }
    }

    private static void require(boolean condition, String message) {
        if (!condition) {
            throw new AssertionError(message);
        }
    }

    public static void main(String[] args) {
        RecordingActions blockedActions = new RecordingActions();
        blockedActions.allowStart = false;
        ReceiverLifecycleCoordinator blocked =
                new ReceiverLifecycleCoordinator(blockedActions);
        blocked.onResume();
        blocked.onSurfaceCreated();
        require(blockedActions.starts == 0 && blockedActions.startAttempts == 1,
                "a missing permission may defer server startup");
        blockedActions.allowStart = true;
        blocked.reevaluate();
        require(blockedActions.starts == 1 && blockedActions.startAttempts == 2,
                "permission reevaluation must retry a previously deferred start");

        RecordingActions actions = new RecordingActions();
        ReceiverLifecycleCoordinator coordinator =
                new ReceiverLifecycleCoordinator(actions);

        coordinator.onResume();
        coordinator.onSurfaceCreated();
        coordinator.onResume();
        require(actions.starts == 1,
                "resume and surface events must start exactly one server");

        coordinator.onPause();
        require(actions.stops == 0,
                "onPause must not stop a server while its surface remains valid");

        coordinator.onSurfaceDestroyed();
        require(actions.stops == 1,
                "surface loss must stop the current server exactly once");

        coordinator.onSurfaceCreated();
        require(actions.starts == 1,
                "a paused Activity must wait for resume before restarting");
        coordinator.onResume();
        require(actions.starts == 2,
                "a recreated foreground surface must restart the server");

        coordinator.reevaluate();
        require(actions.starts == 2,
                "permission reevaluation must remain idempotent");

        coordinator.onDestroy();
        coordinator.onDestroy();
        require(actions.stops == 2,
                "destroy cleanup must stop the active server only once");

        System.out.println("ReceiverLifecycleSelfTest PASS");
    }
}

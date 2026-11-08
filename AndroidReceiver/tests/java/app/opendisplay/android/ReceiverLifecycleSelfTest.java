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
        require(ReceiverPermissionPolicy.canStartTcpServer(false),
                "USB TCP server must not depend on nearby-WiFi permission");
        require(!ReceiverPermissionPolicy.shouldAdvertiseWifi(false),
                "NSD advertising must wait for nearby-WiFi permission");
        require(ReceiverPermissionPolicy.shouldAdvertiseWifi(true),
                "NSD advertising may start after nearby-WiFi permission is granted");

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
        require(actions.stops == 1,
                "onPause must close the receiver so Mac removes its virtual display");

        coordinator.onSurfaceDestroyed();
        require(actions.stops == 1,
                "surface loss after pause must not stop the receiver twice");

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

        RecordingActions securityActions = new RecordingActions();
        securityActions.allowStart = false;
        ReceiverLifecycleCoordinator security = new ReceiverLifecycleCoordinator(securityActions);
        security.onResume(); security.onSurfaceCreated();
        security.stopForSettings();
        securityActions.allowStart = true;
        security.reevaluate(); security.onPause();
        require(securityActions.starts == 1 && securityActions.stops == 1,
                "repaired identity must remain owned by lifecycle and close on background");
        security.onResume(); security.stopForSettings(); security.reevaluate();
        require(securityActions.starts == 3 && securityActions.stops == 2,
                "security mode switch must stop before starting one replacement");
        security.onDestroy();
        require(securityActions.stops == 3, "replacement leaked after destroy");

        RecordingActions connectedActions = new RecordingActions();
        ReceiverLifecycleCoordinator connected =
                new ReceiverLifecycleCoordinator(connectedActions);
        connected.onResume();
        connected.onSurfaceCreated();
        require(connectedActions.starts == 1 && connectedActions.stops == 0,
                "initial foreground server must start");
        connected.onConnectionChanged(true);
        connected.onPause();
        connected.onSurfaceDestroyed();
        require(connectedActions.stops == 0,
                "an active connected session must survive background surface loss");
        connected.onSurfaceCreated();
        connected.onResume();
        require(connectedActions.starts == 1 && connectedActions.stops == 0,
                "returning to foreground must reuse the preserved connected server");
        connected.onPause();
        connected.onSurfaceDestroyed();
        connected.onConnectionChanged(false);
        require(connectedActions.stops == 1,
                "disconnecting while backgrounded must stop the preserved server immediately");
        connected.onSurfaceCreated();
        connected.onResume();
        require(connectedActions.starts == 2,
                "foreground return after background disconnect must start a fresh server");
        connected.onDestroy();
        require(connectedActions.stops == 2,
                "destroy after connected session must stop server cleanly");
        System.out.println("ReceiverLifecycleSelfTest PASS");
    }
}

package app.opendisplay.android;

final class ReceiverConnectionCoordinator {
    interface Actions {
        void resetQueuedFrames();
        void releaseDecoder();
        void setConnected(boolean connected);
        void stopStreaming();
        void onConnectionState(ReceiverConnectionStateSnapshot state);
    }

    private final Actions actions;
    private long currentGeneration;
    private boolean connected;

    ReceiverConnectionCoordinator(Actions actions) {
        this.actions = actions;
    }

    boolean onConnected(long generation, String reason) {
        boolean replacing;
        synchronized (this) {
            if (generation <= currentGeneration) {
                return false;
            }
            replacing = connected;
            currentGeneration = generation;
            connected = true;
        }
        actions.resetQueuedFrames();
        if (replacing) {
            actions.releaseDecoder();
            actions.stopStreaming();
        }
        actions.setConnected(true);
        publish(ReceiverConnectionState.SOCKET_CONNECTED, reason, generation);
        return true;
    }

    boolean onDisconnected(long generation, String reason) {
        synchronized (this) {
            if (!isCurrentLocked(generation)) {
                return false;
            }
            connected = false;
        }
        actions.resetQueuedFrames();
        actions.releaseDecoder();
        actions.setConnected(false);
        actions.stopStreaming();
        publish(ReceiverConnectionState.DISCONNECTED, reason, generation);
        return true;
    }

    boolean onError(long generation, String reason) {
        synchronized (this) {
            if (!isCurrentLocked(generation)) {
                return false;
            }
            publish(ReceiverConnectionState.FAILED, reason, generation);
        }
        return true;
    }

    boolean transition(long generation, ReceiverConnectionState state, String reason) {
        return transition(generation, state, reason, 0, 0);
    }

    boolean transition(long generation, ReceiverConnectionState state, String reason,
                       long sessionEpoch, long configVersion) {
        synchronized (this) {
            if (!isCurrentLocked(generation)) {
                return false;
            }
            publish(state, reason, generation, sessionEpoch, configVersion);
        }
        return true;
    }

    synchronized boolean isCurrent(long generation) {
        return isCurrentLocked(generation);
    }

    synchronized long currentGeneration() {
        return currentGeneration;
    }

    private boolean isCurrentLocked(long generation) {
        return connected && generation > 0 && generation == currentGeneration;
    }

    private void publish(ReceiverConnectionState state, String reason, long generation) {
        publish(state, reason, generation, 0, 0);
    }

    private void publish(ReceiverConnectionState state, String reason, long generation,
                         long sessionEpoch, long configVersion) {
        actions.onConnectionState(new ReceiverConnectionStateSnapshot(
                state, reason, System.currentTimeMillis(), generation,
                sessionEpoch, configVersion));
    }
}

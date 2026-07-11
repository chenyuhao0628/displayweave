package app.opendisplay.android;

final class ReceiverConnectionCoordinator {
    interface Actions {
        void resetQueuedFrames();
        void releaseDecoder();
        void setConnected(boolean connected);
        void stopStreaming();
    }

    private final Actions actions;

    ReceiverConnectionCoordinator(Actions actions) {
        this.actions = actions;
    }

    void onConnected() {
        actions.resetQueuedFrames();
        actions.setConnected(true);
    }

    void onDisconnected() {
        actions.resetQueuedFrames();
        actions.releaseDecoder();
        actions.setConnected(false);
        actions.stopStreaming();
    }
}

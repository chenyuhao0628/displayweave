package app.opendisplay.android;

final class DecodeWorkerState {
    private boolean scheduled;

    boolean markFrameAvailable() {
        if (scheduled) {
            return false;
        }
        scheduled = true;
        return true;
    }

    void markQueueReset() {
        // The queued frame is gone, but an executor task may still be running.
        // Only that worker may transition this state back to idle.
    }

    void markIdle() {
        scheduled = false;
    }

    boolean markIdleAndCheckForPendingFrame(boolean hasPendingFrame) {
        scheduled = false;
        return hasPendingFrame && markFrameAvailable();
    }
}

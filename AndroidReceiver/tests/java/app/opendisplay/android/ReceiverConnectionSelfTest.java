package app.opendisplay.android;

public final class ReceiverConnectionSelfTest {
    private static final class RecordingActions
            implements ReceiverConnectionCoordinator.Actions {
        int queueResets;
        int decoderReleases;
        int connectedChanges;
        int streamingStops;

        @Override
        public void resetQueuedFrames() {
            queueResets++;
        }

        @Override
        public void releaseDecoder() {
            decoderReleases++;
        }

        @Override
        public void setConnected(boolean connected) {
            connectedChanges++;
        }

        @Override
        public void stopStreaming() {
            streamingStops++;
        }
    }

    private static void require(boolean condition, String message) {
        if (!condition) {
            throw new AssertionError(message);
        }
    }

    public static void main(String[] args) {
        RecordingActions actions = new RecordingActions();
        ReceiverConnectionCoordinator coordinator =
                new ReceiverConnectionCoordinator(actions);

        coordinator.onConnected();
        require(actions.queueResets == 1 && actions.connectedChanges == 1,
                "new transport connections must begin with an empty frame queue");
        require(actions.decoderReleases == 0,
                "a new connection does not release a decoder before use");

        coordinator.onDisconnected();
        require(actions.queueResets == 2,
                "disconnect must discard frames from the old transport generation");
        require(actions.decoderReleases == 1,
                "disconnect must release the old predictive decoder chain");
        require(actions.connectedChanges == 2 && actions.streamingStops == 1,
                "disconnect must update connected and streaming state");

        DecodeWorkerState workerState = new DecodeWorkerState();
        require(workerState.markFrameAvailable(),
                "the first frame must schedule one decoder worker");
        require(!workerState.markFrameAvailable(),
                "later frames must not schedule a concurrent decoder worker");
        workerState.markQueueReset();
        require(!workerState.markFrameAvailable(),
                "connection reset must not forget an already scheduled worker");
        workerState.markIdle();
        require(workerState.markFrameAvailable(),
                "a frame arriving after the worker becomes idle must schedule work");

        System.out.println("ReceiverConnectionSelfTest PASS");
    }
}

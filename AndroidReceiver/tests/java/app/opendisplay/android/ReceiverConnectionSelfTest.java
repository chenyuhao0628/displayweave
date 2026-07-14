package app.opendisplay.android;

import java.util.ArrayList;
import java.util.List;

public final class ReceiverConnectionSelfTest {
    private static final class RecordingActions
            implements ReceiverConnectionCoordinator.Actions {
        int queueResets;
        int decoderReleases;
        int connectedChanges;
        int streamingStops;
        final List<ReceiverConnectionStateSnapshot> states = new ArrayList<>();

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

        @Override
        public void onConnectionState(ReceiverConnectionStateSnapshot state) {
            states.add(state);
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

        require(coordinator.onConnected(1, "accepted"),
                "the first generation must become current");
        require(actions.queueResets == 1 && actions.connectedChanges == 1,
                "new transport connections must begin with an empty frame queue");
        require(actions.decoderReleases == 0,
                "a new connection does not release a decoder before use");
        require(coordinator.isCurrent(1) && coordinator.currentGeneration() == 1,
                "the first accepted socket must own generation 1");
        require(actions.states.get(0).state == ReceiverConnectionState.SOCKET_CONNECTED,
                "accepted socket must enter SOCKET_CONNECTED");
        require(actions.states.get(0).generation == 1
                        && "accepted".equals(actions.states.get(0).reason),
                "state events must carry generation and reason");

        require(coordinator.transition(1, ReceiverConnectionState.HELLO_SENT, "helloSent"),
                "the current generation may advance connection state");
        require(coordinator.transition(1, ReceiverConnectionState.DECODER_CONFIGURING,
                        "configAccepted", 8, 12),
                "negotiated state may publish epoch and config version");
        ReceiverConnectionStateSnapshot negotiated =
                actions.states.get(actions.states.size() - 1);
        require(negotiated.sessionEpoch == 8 && negotiated.configVersion == 12,
                "connection state must carry negotiated session/config identity");
        require(!coordinator.transition(0, ReceiverConnectionState.FAILED, "staleError"),
                "a stale generation must not publish connection state");

        require(coordinator.onConnected(2, "replacementAccepted"),
                "a newer generation must replace the current connection");
        require(coordinator.currentGeneration() == 2 && coordinator.isCurrent(2),
                "the replacement must become the only current generation");
        require(actions.queueResets == 2,
                "replacement must discard queued frames from the old generation");
        require(actions.decoderReleases == 1 && actions.streamingStops == 1,
                "replacement must retire the old decoder and streaming state");

        int stateCountBeforeStaleEvents = actions.states.size();
        require(!coordinator.onError(1, "oldWriterFailure"),
                "an old writer failure must be ignored after replacement");
        require(!coordinator.onDisconnected(1, "oldReaderExit"),
                "an old reader disconnect must be ignored after replacement");
        require(actions.states.size() == stateCountBeforeStaleEvents,
                "stale callbacks must not publish UI state");
        require(actions.decoderReleases == 1 && actions.streamingStops == 1,
                "stale callbacks must not release the current decoder or stop streaming");

        require(coordinator.onDisconnected(2, "readerExit"),
                "the current reader disconnect must be applied");
        require(actions.queueResets == 3,
                "current disconnect must discard frames from its generation");
        require(actions.decoderReleases == 2,
                "disconnect must release the old predictive decoder chain");
        require(actions.connectedChanges == 3 && actions.streamingStops == 2,
                "disconnect must update connected and streaming state");
        ReceiverConnectionStateSnapshot disconnected =
                actions.states.get(actions.states.size() - 1);
        require(disconnected.state == ReceiverConnectionState.DISCONNECTED
                        && disconnected.generation == 2,
                "disconnect state must identify the generation that ended");

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

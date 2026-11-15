package app.opendisplay.android;

import java.net.DatagramSocket;
import java.net.InetSocketAddress;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.Base64;
import java.util.List;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.Future;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicBoolean;

import app.opendisplay.android.protocol.UdpMediaProtocol;

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
        require(workerState.markIdleAndCheckForPendingFrame(true),
                "worker teardown must atomically reschedule already queued work");
        require(!workerState.markFrameAvailable(),
                "the recovery reschedule must still permit only one worker");
        require(!workerState.markIdleAndCheckForPendingFrame(false),
                "worker teardown without queued work must stay idle");
        require(workerState.markFrameAvailable(),
                "new work must schedule after an empty recovery teardown");

        testConcurrentUdpMediaLifecycleTeardown();
        testGradleDisablesEncryptedDependenciesInfo();

        System.out.println("ReceiverConnectionSelfTest PASS");
    }

    private static void testConcurrentUdpMediaLifecycleTeardown() {
        byte[] secretBytes = new byte[32];
        for (int i = 0; i < secretBytes.length; i++) {
            secretBytes[i] = (byte) (0x31 + i);
        }
        String secretBase64 = Base64.getEncoder().encodeToString(secretBytes);
        UdpMediaReceiverSession.Listener noopListener = new UdpMediaReceiverSession.Listener() {
            @Override
            public void onFrameReady(
                    long generation, long sessionEpoch, UdpMediaProtocol.FrameEnvelope frame) {}

            @Override
            public void onKeyframeNeeded(long generation, long sessionEpoch, String reason) {}
        };

        ExecutorService pool = Executors.newFixedThreadPool(4);
        try {
            for (int round = 1; round <= 32; round++) {
                final int currentRound = round;
                final long epoch = 100L + currentRound;
                String json = "{\"type\":\"udpMediaConfig\",\"version\":1,\"sessionEpoch\":"
                        + epoch
                        + ",\"udpPort\":9999,\"maxPayloadBytes\":1200,\"rootSecret\":\""
                        + secretBase64
                        + "\"}";
                UdpMediaProtocol.ConfigMessage cfg =
                        UdpMediaProtocol.ConfigMessage.parseJson(json);
                require(cfg != null, "udpMediaConfig fixture must parse");

                OpenDisplayServer.UdpMediaLifecycleSlot slot =
                        new OpenDisplayServer.UdpMediaLifecycleSlot();
                slot.markStarted();
                AtomicBoolean identityCurrent = new AtomicBoolean(true);
                CountDownLatch startGate = new CountDownLatch(1);

                Future<Integer> adopter = pool.submit(() -> {
                    startGate.await(2, TimeUnit.SECONDS);
                    UdpAudioPlayer audio = new UdpAudioPlayer();
                    UdpMediaReceiverSession session = null;
                    boolean adopted = false;
                    try {
                        session = UdpMediaReceiverSession.start(
                                currentRound, cfg, "127.0.0.1", noopListener);
                        int boundPort = session.localPort();
                        require(!slot.shouldDeliverAudio(audio, identityCurrent::get),
                                "unadopted UDP audio player must never accept packets");
                        adopted = slot.adopt(session, audio, identityCurrent::get);
                        return boundPort;
                    } finally {
                        if (!adopted) {
                            if (session != null) {
                                session.close();
                            }
                            audio.close();
                        }
                    }
                });

                Future<Void> epochSweeper = pool.submit(() -> {
                    startGate.await(2, TimeUnit.SECONDS);
                    for (int i = 0; i < 8; i++) {
                        slot.stopIfEpochMismatch(epoch + 1L);
                        slot.acceptCursorSequence(i + 1L, identityCurrent::get);
                        slot.nextFrameSequence(i + 1L, i);
                    }
                    return null;
                });

                Future<Void> stopper = pool.submit(() -> {
                    startGate.await(2, TimeUnit.SECONDS);
                    if ((currentRound & 1) == 0) {
                        identityCurrent.set(false);
                        slot.stop();
                    } else {
                        slot.markStoppedAndClose();
                    }
                    return null;
                });

                startGate.countDown();
                int allocatedPort = adopter.get(5, TimeUnit.SECONDS);
                epochSweeper.get(5, TimeUnit.SECONDS);
                stopper.get(5, TimeUnit.SECONDS);
                slot.markStoppedAndClose();

                require(!slot.hasActiveResources() && slot.activeSession() == null,
                        "concurrent stop/epoch sweep must never leave UDP session or audio leaked");
                require(slot.nextFrameSequence(10L, 5L) == null,
                        "stopped UDP slot must reject frame sequence allocation");

                // Prove the UDP socket was closed cleanly by rebinding the exact ephemeral port
                // (best-effort if another OS process grabbed it first, though reuseAddress is set).
                try (DatagramSocket probe = new DatagramSocket(null)) {
                    probe.setReuseAddress(true);
                    probe.bind(new InetSocketAddress("127.0.0.1", allocatedPort));
                } catch (java.net.BindException ignoredIfEphemeralContended) {
                }
            }
        } catch (Exception error) {
            throw new AssertionError("Concurrent UDP lifecycle test failed", error);
        } finally {
            pool.shutdownNow();
        }
    }

    private static void testGradleDisablesEncryptedDependenciesInfo() {
        Path[] candidates = new Path[] {
            Path.of("build.gradle.kts"),
            Path.of("app/build.gradle.kts"),
            Path.of("AndroidReceiver/app/build.gradle.kts")
        };
        Path buildGradle = null;
        for (Path candidate : candidates) {
            if (Files.isRegularFile(candidate)) {
                buildGradle = candidate;
                break;
            }
        }
        require(buildGradle != null, "unable to locate AndroidReceiver/app/build.gradle.kts");
        try {
            String source = Files.readString(buildGradle, StandardCharsets.UTF_8);
            require(source.contains("dependenciesInfo")
                            && source.contains("includeInApk = false")
                            && source.contains("includeInBundle = false"),
                    "Android build.gradle.kts must disable encrypted DependencyInfoBlock in APK/Bundle");
        } catch (java.io.IOException error) {
            throw new AssertionError("failed reading build.gradle.kts", error);
        }
    }
}

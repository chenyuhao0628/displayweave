package app.opendisplay.android;

import java.io.IOException;
import java.net.DatagramPacket;
import java.net.DatagramSocket;
import java.net.InetAddress;
import java.net.InetSocketAddress;
import java.net.SocketAddress;
import java.net.SocketTimeoutException;
import java.nio.charset.StandardCharsets;
import java.security.GeneralSecurityException;
import java.util.List;

import app.opendisplay.android.protocol.UdpMediaProtocol;

/**
 * Session-scoped UDP media receiver for {@code udpMediaV1}.
 * Owns a single daemon thread that performs non-blocking/5ms-bounded datagram
 * reads, AES-128-GCM verification, Cauchy/XOR FEC recovery, NACK emission,
 * jitter-buffer release, and 30ms delay-gradient feedback.
 */
public final class UdpMediaReceiverSession implements AutoCloseable {
    public interface Listener {
        void onFrameReady(long generation, long sessionEpoch, UdpMediaProtocol.FrameEnvelope frame);
        void onKeyframeNeeded(long generation, long sessionEpoch, String reason);
    }

    private static final int SOCKET_TIMEOUT_MS = 5;
    private static final long MAINTENANCE_INTERVAL_NS = 5_000_000L;
    private static final long PROBE_RETRY_INTERVAL_NS = 150_000_000L;
    private static final int MAX_INITIAL_PROBES = 6;
    private static final byte[] PROBE_PAYLOAD =
            "DWV1-RCV-PROBE".getBytes(StandardCharsets.UTF_8);

    public final long generation;
    public final long sessionEpoch;
    private final UdpMediaProtocol.CryptoSession crypto;
    private final UdpMediaProtocol.Reassembler reassembler = new UdpMediaProtocol.Reassembler();
    private final UdpMediaProtocol.JitterBuffer jitterBuffer = new UdpMediaProtocol.JitterBuffer();
    private final UdpMediaProtocol.ArrivalEstimator arrivalEstimator =
            new UdpMediaProtocol.ArrivalEstimator();
    private final DatagramSocket socket;
    private final int localPort;
    private final Listener listener;
    private final Thread workerThread;

    private volatile boolean running = true;
    private volatile SocketAddress senderAddress;
    private volatile long currentRttUs = 10_000L;
    private volatile int currentDecodeQueueMs = 0;
    private volatile int currentRenderFps = 60;
    private boolean receivedAnySenderPacket = false;
    private int probesSent = 0;
    private long lastProbeSentNs = 0;

    private UdpMediaReceiverSession(
            long generation,
            UdpMediaProtocol.ConfigMessage config,
            SocketAddress initialSenderAddress,
            DatagramSocket socket,
            Listener listener) {
        this.generation = generation;
        this.sessionEpoch = config.sessionEpoch;
        UdpMediaProtocol.KeyMaterial keyMaterial =
                UdpMediaProtocol.KeyMaterial.derive(config.rootSecret, config.sessionEpoch);
        this.crypto = new UdpMediaProtocol.CryptoSession(keyMaterial);
        this.senderAddress = initialSenderAddress;
        this.socket = socket;
        this.localPort = socket.getLocalPort();
        this.listener = listener;
        this.workerThread = new Thread(
                this::runLoop,
                "DisplayWeave-UDP-Rcv-" + generation + "-" + config.sessionEpoch);
        this.workerThread.setDaemon(true);
    }

    public static UdpMediaReceiverSession start(
            long generation,
            UdpMediaProtocol.ConfigMessage config,
            String senderHost,
            Listener listener) throws IOException {
        if (config == null || listener == null) {
            throw new IllegalArgumentException("UDP config and listener required");
        }
        SocketAddress initialPeer = null;
        if (senderHost != null && !senderHost.isEmpty() && config.udpPort > 0) {
            try {
                InetAddress addr = InetAddress.getByName(senderHost);
                initialPeer = new InetSocketAddress(addr, config.udpPort);
            } catch (IOException ignored) {
                initialPeer = null;
            }
        }
        DatagramSocket datagramSocket = new DatagramSocket(null);
        try {
            datagramSocket.setReuseAddress(true);
            datagramSocket.bind(new InetSocketAddress(0));
            datagramSocket.setSoTimeout(SOCKET_TIMEOUT_MS);
            try {
                datagramSocket.setReceiveBufferSize(1024 * 1024);
                datagramSocket.setSendBufferSize(512 * 1024);
            } catch (IOException ignored) {
            }
        } catch (IOException error) {
            datagramSocket.close();
            throw error;
        }
        UdpMediaReceiverSession session = new UdpMediaReceiverSession(
                generation, config, initialPeer, datagramSocket, listener);
        session.workerThread.start();
        return session;
    }

    public int localPort() {
        return localPort;
    }

    public void updateTelemetry(double rttMs, int decodeQueueMs, int renderFps) {
        if (Double.isFinite(rttMs) && rttMs > 0) {
            currentRttUs = Math.max(1_000L, Math.min(500_000L, Math.round(rttMs * 1_000.0)));
        }
        currentDecodeQueueMs = Math.max(0, Math.min(65535, decodeQueueMs));
        currentRenderFps = Math.max(0, Math.min(65535, renderFps));
    }

    @Override
    public void close() {
        running = false;
        socket.close();
    }

    private void runLoop() {
        byte[] buffer = new byte[UdpMediaProtocol.MAX_DATAGRAM_BYTES + 64];
        DatagramPacket packet = new DatagramPacket(buffer, buffer.length);
        long lastMaintenanceNs = System.nanoTime();
        sendProbe(false, lastMaintenanceNs);

        while (running && !socket.isClosed()) {
            try {
                packet.setLength(buffer.length);
                socket.receive(packet);
                long nowNs = System.nanoTime();
                handleIncomingDatagram(buffer, packet.getLength(), packet.getSocketAddress(), nowNs);
                if ((nowNs - lastMaintenanceNs) >= MAINTENANCE_INTERVAL_NS) {
                    runMaintenance(nowNs);
                    lastMaintenanceNs = nowNs;
                }
            } catch (SocketTimeoutException timeout) {
                long nowNs = System.nanoTime();
                runMaintenance(nowNs);
                lastMaintenanceNs = nowNs;
            } catch (IOException error) {
                if (!running || socket.isClosed()) {
                    break;
                }
            } catch (RuntimeException error) {
                // Keep UDP loop alive across any unexpected packet anomaly.
            }
        }
        jitterBuffer.reset();
    }

    private void handleIncomingDatagram(
            byte[] data, int length, SocketAddress sourceAddress, long nowNs) {
        UdpMediaProtocol.AuthenticatedPacket authenticated;
        try {
            authenticated = crypto.open(data, length, UdpMediaProtocol.DIR_SENDER_TO_RECEIVER);
        } catch (GeneralSecurityException | IllegalArgumentException rejected) {
            return;
        }
        receivedAnySenderPacket = true;
        if (sourceAddress != null) {
            senderAddress = sourceAddress;
        }
        if (authenticated.header.packetType == UdpMediaProtocol.PACKET_PROBE) {
            if ((authenticated.header.flags & UdpMediaProtocol.FLAG_PROBE_ACK) == 0) {
                sendProbe(true, nowNs);
            }
            return;
        }

        arrivalEstimator.recordPacket(
                authenticated.extendedSequence,
                authenticated.header.sendTimeUs,
                nowNs);

        UdpMediaProtocol.FrameEnvelope assembled = reassembler.ingest(authenticated, nowNs);
        if (assembled != null) {
            UdpMediaProtocol.JitterBuffer.PollResult poll = jitterBuffer.insert(assembled, nowNs);
            for (UdpMediaProtocol.FrameEnvelope frame : poll.deliverable) {
                if (!running) {
                    return;
                }
                listener.onFrameReady(generation, sessionEpoch, frame);
            }
            if (poll.needsKeyframe || reassembler.consumeKeyframeRequestFlag()) {
                listener.onKeyframeNeeded(generation, sessionEpoch, "udpJitterOrLoss");
            }
        } else if (reassembler.consumeKeyframeRequestFlag()) {
            listener.onKeyframeNeeded(generation, sessionEpoch, "udpReassemblyExpired");
        }

        emitFeedbackIfDue(nowNs);
    }

    private void runMaintenance(long nowNs) {
        if (!running) {
            return;
        }
        if (!receivedAnySenderPacket
                && probesSent < MAX_INITIAL_PROBES
                && (nowNs - lastProbeSentNs) >= PROBE_RETRY_INTERVAL_NS) {
            sendProbe(false, nowNs);
        }

        SocketAddress dest = senderAddress;
        if (dest != null) {
            List<UdpMediaProtocol.NackPayload> nacks = reassembler.pollNacks(nowNs, currentRttUs);
            for (UdpMediaProtocol.NackPayload nack : nacks) {
                try {
                    byte[] datagram = crypto.seal(
                            UdpMediaProtocol.DIR_RECEIVER_TO_SENDER,
                            UdpMediaProtocol.PACKET_NACK,
                            0,
                            nowSendTimeUs(nowNs),
                            nack.frameId,
                            nack.baseFragIndex,
                            nack.missingCount,
                            nack.encode());
                    sendDatagram(datagram, dest);
                } catch (GeneralSecurityException ignored) {
                }
            }
        }

        UdpMediaProtocol.JitterBuffer.PollResult poll = jitterBuffer.pollDeliverable(nowNs);
        for (UdpMediaProtocol.FrameEnvelope frame : poll.deliverable) {
            if (!running) {
                return;
            }
            listener.onFrameReady(generation, sessionEpoch, frame);
        }
        if (poll.needsKeyframe || reassembler.consumeKeyframeRequestFlag()) {
            listener.onKeyframeNeeded(generation, sessionEpoch, "udpMaintenanceRecovery");
        }

        emitFeedbackIfDue(nowNs);
    }

    private void emitFeedbackIfDue(long nowNs) {
        SocketAddress dest = senderAddress;
        if (dest == null) {
            return;
        }
        UdpMediaProtocol.FeedbackPayload feedback = arrivalEstimator.pollFeedbackIfDue(
                nowNs, currentDecodeQueueMs, currentRenderFps);
        if (feedback == null) {
            return;
        }
        try {
            byte[] datagram = crypto.seal(
                    UdpMediaProtocol.DIR_RECEIVER_TO_SENDER,
                    UdpMediaProtocol.PACKET_FEEDBACK,
                    0,
                    nowSendTimeUs(nowNs),
                    feedback.highestSeq & 0xFFFF_FFFFL,
                    0,
                    1,
                    feedback.encode());
            sendDatagram(datagram, dest);
        } catch (GeneralSecurityException ignored) {
        }
    }

    private void sendProbe(boolean isAck, long nowNs) {
        SocketAddress dest = senderAddress;
        if (dest == null) {
            return;
        }
        int flags = isAck ? UdpMediaProtocol.FLAG_PROBE_ACK : 0;
        try {
            byte[] datagram = crypto.seal(
                    UdpMediaProtocol.DIR_RECEIVER_TO_SENDER,
                    UdpMediaProtocol.PACKET_PROBE,
                    flags,
                    nowSendTimeUs(nowNs),
                    0,
                    0,
                    1,
                    PROBE_PAYLOAD);
            sendDatagram(datagram, dest);
            if (!isAck) {
                probesSent++;
                lastProbeSentNs = nowNs;
            }
        } catch (GeneralSecurityException ignored) {
        }
    }

    private void sendDatagram(byte[] data, SocketAddress dest) {
        if (!running || socket.isClosed() || dest == null) {
            return;
        }
        try {
            DatagramPacket packet = new DatagramPacket(data, data.length, dest);
            socket.send(packet);
        } catch (IOException ignored) {
        }
    }

    private static long nowSendTimeUs(long nowNs) {
        return (nowNs / 1_000L) & 0xFFFF_FFFFL;
    }
}

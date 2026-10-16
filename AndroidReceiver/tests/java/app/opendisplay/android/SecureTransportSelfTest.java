package app.opendisplay.android;

import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.net.Socket;
import java.security.KeyPair;
import java.security.KeyPairGenerator;
import java.security.cert.X509Certificate;
import java.util.Arrays;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.concurrent.atomic.AtomicLong;
import javax.net.ssl.SSLSocket;

public final class SecureTransportSelfTest {
    private static final class Identity {
        final KeyPair pair;
        final X509Certificate cert;
        Identity(java.security.PrivateKey key, X509Certificate certificate) {
            pair = new KeyPair(certificate.getPublicKey(), key); cert = certificate;
        }
        Identity() throws Exception {
            KeyPairGenerator generator = KeyPairGenerator.getInstance("EC"); generator.initialize(256);
            pair = generator.generateKeyPair(); cert = TransportCertificate.create(pair.getPrivate(), pair.getPublic());
        }
    }
    private static void expect(boolean value, String message) { if (!value) throw new AssertionError(message); }
    private static SSLSocket client(int port, Identity identity, String serverPin) throws Exception {
        SSLSocket socket = (SSLSocket) SecureTls.context(identity.pair.getPrivate(), identity.cert, serverPin::equals)
                .getSocketFactory().createSocket("127.0.0.1", port);
        SecureTls.configure(socket, true); socket.setSoTimeout(4000); socket.startHandshake();
        return socket;
    }
    private static boolean closed(Socket socket) throws IOException {
        socket.setSoTimeout(4000);
        try { return socket.getInputStream().read() == -1; }
        catch (java.net.SocketTimeoutException error) { return false; }
        catch (IOException error) { return true; }
    }
    private static void rejectTamperedRecord(int port, Identity identity, String pin, byte[] token) throws Exception {
        java.util.concurrent.ExecutorService relay = java.util.concurrent.Executors.newFixedThreadPool(2);
        java.util.concurrent.atomic.AtomicReference<Socket> front = new java.util.concurrent.atomic.AtomicReference<>();
        java.util.concurrent.atomic.AtomicReference<Socket> back = new java.util.concurrent.atomic.AtomicReference<>();
        java.util.concurrent.atomic.AtomicBoolean tampered = new java.util.concurrent.atomic.AtomicBoolean();
        try (java.net.ServerSocket proxy = new java.net.ServerSocket(0, 1, java.net.InetAddress.getByName("127.0.0.1"))) {
            proxy.setSoTimeout(4000);
            relay.execute(() -> {
                try (Socket downstream = proxy.accept(); Socket upstream = new Socket("127.0.0.1", port)) {
                    front.set(downstream); back.set(upstream);
                    downstream.setSoTimeout(4000); upstream.setSoTimeout(4000);
                    relay.execute(() -> {
                        try {
                            byte[] buffer = new byte[18432]; int count;
                            while ((count = upstream.getInputStream().read(buffer)) != -1) {
                                downstream.getOutputStream().write(buffer, 0, count);
                            }
                        } catch (IOException ignored) { }
                        finally { try { downstream.close(); } catch (IOException ignored) { } }
                    });
                    java.io.DataInputStream input = new java.io.DataInputStream(downstream.getInputStream());
                    while (true) {
                        byte[] header = new byte[5]; input.readFully(header);
                        int length = (header[3] & 255) << 8 | (header[4] & 255);
                        if (length <= 0 || length > 18432) throw new IOException("TLS test record bound");
                        byte[] record = new byte[length]; input.readFully(record);
                        // TLS 1.2 application records are encrypted and authenticated.
                        if (header[0] == 23 && tampered.compareAndSet(false, true)) record[length - 1] ^= 1;
                        upstream.getOutputStream().write(header); upstream.getOutputStream().write(record);
                    }
                } catch (IOException ignored) { }
            });
            try (SSLSocket probe = (SSLSocket) SecureTls.context(identity.pair.getPrivate(), identity.cert, pin::equals)
                    .getSocketFactory().createSocket("127.0.0.1", proxy.getLocalPort())) {
                SecureTls.configure(probe, true); probe.setEnabledProtocols(new String[]{"TLSv1.2"});
                probe.setSoTimeout(4000); probe.startHandshake();
                SecureSocketAdmission.writeFrame(probe.getOutputStream(), new SecurePairingProtocol.Auth("stranger", "Test", token).encode());
                expect(closed(probe), "tampered TLS application record was accepted");
                expect(tampered.get(), "tamper test never modified a TLS application record");
            }
        } finally {
            for (Socket socket : new Socket[]{front.get(), back.get()}) {
                if (socket != null) try { socket.close(); } catch (IOException ignored) { }
            }
            relay.shutdownNow(); expect(relay.awaitTermination(5, TimeUnit.SECONDS), "TLS test relay leaked workers");
        }
    }
    public static void main(String[] args) throws Exception { run(); }
    static void run() throws Exception { run(new Identity()); }
    static void run(java.security.PrivateKey key, X509Certificate certificate) throws Exception { run(new Identity(key, certificate)); }
    private static void run(Identity receiver) throws Exception {
        Identity sender = new Identity(), stranger = new Identity();
        String pin = SecureTls.fingerprint(receiver.cert);
        SecurePairingState pairing = new SecurePairingState("receiver", pin, null,
                () -> System.nanoTime() / 1_000_000, ignored -> { });
        SecureSocketAdmission security = new SecureSocketAdmission(receiver.pair.getPrivate(), receiver.cert, pairing);
        WifiTcpReceiverTransport transport = new WifiTcpReceiverTransport(0, security, 2000);
        AtomicInteger port = new AtomicInteger(), connections = new AtomicInteger();
        AtomicLong generation = new AtomicLong();
        CountDownLatch listening = new CountDownLatch(1);
        transport.start(new ReceiverTransport.Listener() {
            public void onListening(int actual) { port.set(actual); listening.countDown(); }
            public void onConnected(long value, String peer) { generation.set(value); connections.incrementAndGet(); }
            public void onPayload(long value, byte[] payload) { transport.send(value, payload); }
            public void onDisconnected(long value) { }
            public void onError(long value, String message) { }
        });
        try {
            expect(listening.await(3, TimeUnit.SECONDS), "secure listener did not start");
            SecurePairingProtocol.Invitation invitation = pairing.startPairing();
            try (SSLSocket active = client(port.get(), sender, pin)) {
                byte[] after = "AFTER".getBytes(java.nio.charset.StandardCharsets.UTF_8);
                ByteArrayOutputStream pipelined = new ByteArrayOutputStream();
                SecureSocketAdmission.writeFrame(pipelined, new SecurePairingProtocol.Auth("sender", "Test", invitation.token).encode());
                SecureSocketAdmission.writeFrame(pipelined, after);
                active.getOutputStream().write(pipelined.toByteArray()); active.getOutputStream().flush();
                expect(SecurePairingProtocol.readyIdentity(SecureSocketAdmission.readFrame(active.getInputStream())).equals("receiver"), "ready ID");
                expect(Arrays.equals(SecureSocketAdmission.readFrame(active.getInputStream()), after), "lost coalesced application bytes");
                expect(connections.get() == 1, "TLS/auth did not gate onConnected");
                long first = generation.get();
                SecurePairingProtocol.Invitation extraInvite = pairing.startPairing();
                try (SSLSocket unauthorized = client(port.get(), stranger, pin)) {
                    SecureSocketAdmission.writeFrame(unauthorized.getOutputStream(),
                            new SecurePairingProtocol.Auth("stranger", "Test", new byte[32]).encode());
                    expect(closed(unauthorized), "wrong token was admitted");
                }
                // TLS is necessary but never enough: reject bounded admission
                // framing before the candidate can disturb the active peer.
                for (int length : new int[]{0, 4097, -1}) {
                    try (SSLSocket malformed = client(port.get(), stranger, pin)) {
                        java.io.DataOutputStream output = new java.io.DataOutputStream(malformed.getOutputStream());
                        output.writeInt(length); output.flush();
                        expect(closed(malformed), "malformed admission length accepted");
                    }
                }
                try (SSLSocket trickle = client(port.get(), stranger, pin)) {
                    java.io.DataOutputStream output = new java.io.DataOutputStream(trickle.getOutputStream());
                    output.writeInt(100); output.flush();
                    long start = System.nanoTime();
                    for (int n = 0; n < 15; n++) {
                        try { output.writeByte(0); output.flush(); } catch (IOException expected) { break; }
                        Thread.sleep(200);
                    }
                    expect(closed(trickle), "trickle reset the total admission deadline");
                    expect(System.nanoTime() - start < TimeUnit.SECONDS.toNanos(4), "admission deadline was not absolute");
                }
                rejectTamperedRecord(port.get(), stranger, pin, extraInvite.token);
                expect(connections.get() == 1 && generation.get() == first, "unauthorized candidate replaced active session");
                SecureSocketAdmission.writeFrame(active.getOutputStream(), after);
                expect(Arrays.equals(SecureSocketAdmission.readFrame(active.getInputStream()), after), "active socket was disturbed");
                try (Socket slow1 = new Socket("127.0.0.1", port.get()); Socket slow2 = new Socket("127.0.0.1", port.get())) {
                    long wait = System.nanoTime() + TimeUnit.SECONDS.toNanos(1);
                    while (transport.pendingAdmissionCount() < 2 && System.nanoTime() < wait) Thread.sleep(5);
                    expect(transport.pendingAdmissionCount() == 2, "pending admission cap not reached");
                    try (Socket excess = new Socket("127.0.0.1", port.get())) { expect(closed(excess), "third pending socket accepted"); }
                    expect(closed(slow1) && closed(slow2), "stalled sockets exceeded deadline");
                }
                expect(connections.get() == 1, "stalled socket reached application");
                pairing.revoke("sender"); transport.revokePeer("sender");
                expect(closed(active), "revocation left active TLS socket open");
            }
            pairing.startPairing();
            try (Socket pending = new Socket("127.0.0.1", port.get())) {
                long deadline = System.nanoTime() + TimeUnit.SECONDS.toNanos(1);
                while (transport.pendingAdmissionCount() == 0 && System.nanoTime() < deadline) Thread.sleep(5);
                expect(transport.pendingAdmissionCount() == 1, "shutdown fixture missing pending socket");
                transport.stop();
                expect(closed(pending), "stop leaked pending TLS socket");
            }
        } finally { transport.stop(); }
        expect(transport.pendingAdmissionCount() == 0, "stop left pending admissions");
        System.out.println("SecureTransportSelfTest PASS (TLS admission, preserved frame bytes, active-session isolation, pending bounds, revocation)");
    }
}

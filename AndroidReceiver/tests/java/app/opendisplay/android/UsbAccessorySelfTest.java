/*
 * Copyright (C) 2026 DisplayWeave contributors
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

package app.opendisplay.android;

import java.io.ByteArrayOutputStream;
import java.io.Closeable;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.io.PipedInputStream;
import java.io.PipedOutputStream;
import java.net.Socket;
import java.nio.charset.StandardCharsets;
import java.security.KeyPair;
import java.security.KeyPairGenerator;
import java.security.cert.X509Certificate;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicBoolean;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.concurrent.atomic.AtomicLong;
import java.util.concurrent.atomic.AtomicReference;
import javax.net.ssl.SSLSocket;

import app.opendisplay.android.protocol.LengthPrefixedProtocol;

public final class UsbAccessorySelfTest {
    private static final class Identity {
        final KeyPair pair;
        final X509Certificate cert;

        Identity() throws Exception {
            KeyPairGenerator generator = KeyPairGenerator.getInstance("EC");
            generator.initialize(256);
            pair = generator.generateKeyPair();
            cert = TransportCertificate.create(pair.getPrivate(), pair.getPublic());
        }
    }

    private static final class SimulatedAccessoryLink implements Closeable {
        final UsbAccessoryReceiverTransport.LoopbackAccessoryBridge senderBridge;
        final InputStream receiverIn;
        final OutputStream receiverOut;
        final AtomicBoolean accessoryClosed = new AtomicBoolean(false);

        SimulatedAccessoryLink() throws IOException {
            PipedInputStream toReceiverPipe = new PipedInputStream(65536);
            PipedOutputStream fromSenderPipe = new PipedOutputStream(toReceiverPipe);
            PipedInputStream toSenderPipe = new PipedInputStream(65536);
            PipedOutputStream fromReceiverPipe = new PipedOutputStream(toSenderPipe);

            this.receiverIn = new UsbAccessoryReceiverTransport.PacketInputStream(toReceiverPipe::read);
            this.receiverOut = new UsbAccessoryReceiverTransport.PacketOutputStream(fromReceiverPipe);
            Closeable senderSideClose = () -> {
                closeQuietly(fromSenderPipe);
                closeQuietly(toSenderPipe);
            };
            this.senderBridge = UsbAccessoryReceiverTransport.LoopbackAccessoryBridge.open(
                    new UsbAccessoryReceiverTransport.PacketInputStream(toSenderPipe::read),
                    new UsbAccessoryReceiverTransport.PacketOutputStream(fromSenderPipe),
                    senderSideClose);
        }

        SSLSocket openTlsClient(Identity identity, String serverPin) throws Exception {
            Socket base = senderBridge.serverSocket;
            SSLSocket tls = (SSLSocket) SecureTls.context(
                    identity.pair.getPrivate(), identity.cert, serverPin::equals)
                    .getSocketFactory()
                    .createSocket(base, "127.0.0.1", base.getPort(), true);
            SecureTls.configure(tls, true);
            tls.setSoTimeout(4_000);
            tls.startHandshake();
            return tls;
        }

        Closeable receiverCloseToken() {
            return () -> {
                accessoryClosed.set(true);
                closeQuietly(receiverIn);
                closeQuietly(receiverOut);
            };
        }

        @Override
        public void close() {
            senderBridge.close();
            closeQuietly(receiverIn);
            closeQuietly(receiverOut);
        }
    }

    private static void expect(boolean condition, String message) {
        if (!condition) {
            throw new AssertionError(message);
        }
    }

    private static void closeQuietly(Closeable closeable) {
        if (closeable != null) {
            try {
                closeable.close();
            } catch (IOException ignored) {
            }
        }
    }

    private static boolean closed(Socket socket) throws IOException {
        socket.setSoTimeout(4_000);
        try {
            return socket.getInputStream().read() == -1;
        } catch (java.net.SocketTimeoutException error) {
            return false;
        } catch (IOException error) {
            return true;
        }
    }

    private static void testAccessoryMatching() {
        expect("OpenDisplay".equals(UsbAccessoryReceiverTransport.MANUFACTURER),
                "AOA manufacturer must match Mac USBAccessory wire contract");
        expect("OpenDisplay Receiver".equals(UsbAccessoryReceiverTransport.MODEL),
                "AOA model must match Mac USBAccessory wire contract");
        expect(UsbAccessoryReceiverTransport.isMatchingAccessory(
                "OpenDisplay", "OpenDisplay Receiver"),
                "exact OpenDisplay accessory strings must match");
        expect(!UsbAccessoryReceiverTransport.isMatchingAccessory(
                "ASIX", "AX88179A"),
                "non-DisplayWeave USB hardware must not match");
        expect(!UsbAccessoryReceiverTransport.isMatchingAccessory(null),
                "null UsbAccessory must not match");
    }

    private static void testPacketStreamsAndZlp() throws Exception {
        byte[] source = new byte[40_000];
        for (int i = 0; i < source.length; i++) {
            source[i] = (byte) ((i * 31 + 7) & 0xFF);
        }

        // Scripted USB bulk reads:
        // 16 KiB URB -> 0-byte ZLP -> 16 KiB URB -> two 0-byte ZLPs -> final 7,232 B -> EOF (-1)
        List<Integer> requestedSizes = new ArrayList<>();
        AtomicInteger step = new AtomicInteger();
        UsbAccessoryReceiverTransport.PacketInputStream packetIn =
                new UsbAccessoryReceiverTransport.PacketInputStream((buf, off, len) -> {
                    requestedSizes.add(len);
                    switch (step.getAndIncrement()) {
                        case 0:
                            System.arraycopy(source, 0, buf, off, 16_384);
                            return 16_384;
                        case 1:
                            return 0; // ZLP after packet-aligned write: must NOT be treated as EOF
                        case 2:
                            System.arraycopy(source, 16_384, buf, off, 16_384);
                            return 16_384;
                        case 3:
                        case 4:
                            return 0; // intermittent empty reads
                        case 5:
                            int rem = source.length - 32_768;
                            System.arraycopy(source, 32_768, buf, off, rem);
                            return rem;
                        default:
                            return -1;
                    }
                });

        ByteArrayOutputStream reassembled = new ByteArrayOutputStream();
        byte[] smallBuf = new byte[1_337]; // arbitrary unaligned application read size
        int count;
        while ((count = packetIn.read(smallBuf)) != -1) {
            reassembled.write(smallBuf, 0, count);
        }
        expect(Arrays.equals(source, reassembled.toByteArray()),
                "PacketInputStream must reassemble 40 KB across 16 KiB URBs and ZLPs without data loss");
        for (int req : requestedSizes) {
            expect(req == 16_384,
                    "PacketInputStream must always issue full 16 KiB URB reads to f_accessory");
        }

        // Verify consecutive empty read cap (MAX_EMPTY_READS = 64) prevents infinite spin
        AtomicInteger emptyCalls = new AtomicInteger();
        UsbAccessoryReceiverTransport.PacketInputStream spinStream =
                new UsbAccessoryReceiverTransport.PacketInputStream((buf, off, len) -> {
                    emptyCalls.incrementAndGet();
                    return 0;
                });
        expect(spinStream.read() == -1,
                "64 consecutive empty USB reads must terminate as EOF");
        expect(emptyCalls.get() == UsbAccessoryReceiverTransport.MAX_EMPTY_READS,
                "PacketInputStream must bound consecutive 0-byte reads to 64");

        // Verify PacketOutputStream chunks large writes to <= 16 KiB
        List<Integer> writtenChunks = new ArrayList<>();
        ByteArrayOutputStream sink = new ByteArrayOutputStream();
        OutputStream chunkRecorder = new OutputStream() {
            @Override
            public void write(int b) {
                writtenChunks.add(1);
                sink.write(b);
            }

            @Override
            public void write(byte[] b, int off, int len) {
                writtenChunks.add(len);
                sink.write(b, off, len);
            }
        };
        try (UsbAccessoryReceiverTransport.PacketOutputStream packetOut =
                new UsbAccessoryReceiverTransport.PacketOutputStream(chunkRecorder)) {
            packetOut.write(source);
        }
        expect(Arrays.equals(source, sink.toByteArray()),
                "PacketOutputStream must preserve all outbound bytes");
        expect(writtenChunks.equals(Arrays.asList(16_384, 16_384, 40_000 - 32_768)),
                "PacketOutputStream must split 40,000-byte write into 16 KiB chunks");
    }

    private static void testMutualTlsAdmissionCompositeAndRevocation() throws Exception {
        Identity receiver = new Identity();
        Identity sender = new Identity();
        Identity stranger = new Identity();
        String receiverPin = SecureTls.fingerprint(receiver.cert);

        SecurePairingState pairing = new SecurePairingState(
                "receiver-android",
                receiverPin,
                null,
                () -> System.nanoTime() / 1_000_000,
                ignored -> { });
        SecureSocketAdmission security = new SecureSocketAdmission(
                receiver.pair.getPrivate(), receiver.cert, pairing);

        WifiTcpReceiverTransport wifi = new WifiTcpReceiverTransport(0, security, 2_000);
        UsbAccessoryReceiverTransport usb = new UsbAccessoryReceiverTransport(security, 2_000);
        UsbAccessoryReceiverTransport.Composite composite =
                new UsbAccessoryReceiverTransport.Composite(wifi, usb);

        expect(composite.secure(), "Composite transport must enforce TLS when security is configured");
        expect("wifi".equals(composite.name()), "Idle composite defaults to wifi transport name");

        CountDownLatch listening = new CountDownLatch(1);
        CountDownLatch firstConnected = new CountDownLatch(1);
        CountDownLatch firstPayloadEchoed = new CountDownLatch(1);
        CountDownLatch admissionRejected = new CountDownLatch(1);
        CountDownLatch revokedDisconnect = new CountDownLatch(1);
        AtomicLong activeGeneration = new AtomicLong();
        AtomicInteger connectCount = new AtomicInteger();
        AtomicReference<byte[]> receivedPayload = new AtomicReference<>();

        composite.start(new ReceiverTransport.Listener() {
            @Override
            public void onListening(int port) {
                listening.countDown();
            }

            @Override
            public void onAdmissionRejected(String diagnostic) {
                admissionRejected.countDown();
            }

            @Override
            public void onConnected(long generation, String peer) {
                activeGeneration.set(generation);
                connectCount.incrementAndGet();
                firstConnected.countDown();
            }

            @Override
            public void onPayload(long generation, byte[] payload) {
                receivedPayload.set(payload);
                composite.send(generation, payload);
                firstPayloadEchoed.countDown();
            }

            @Override
            public void onDisconnected(long generation) {
                if (generation == activeGeneration.get()) {
                    revokedDisconnect.countDown();
                }
            }

            @Override
            public void onError(long generation, String message) {
            }
        });

        try {
            expect(listening.await(3, TimeUnit.SECONDS), "TCP/ADB listener must start alongside USB");
            SecurePairingProtocol.Invitation invitation = pairing.startPairing();

            try (SimulatedAccessoryLink activeLink = new SimulatedAccessoryLink()) {
                expect(usb.attachStream(
                        "USB 配件",
                        activeLink.receiverIn,
                        activeLink.receiverOut,
                        activeLink.receiverCloseToken()),
                        "USB accessory stream must be accepted for TLS admission");

                try (SSLSocket tlsClient = activeLink.openTlsClient(sender, receiverPin)) {
                    byte[] coalescedFrame = "{\"type\":\"hello\",\"transport\":\"aoa\"}"
                            .getBytes(StandardCharsets.UTF_8);
                    ByteArrayOutputStream pipelined = new ByteArrayOutputStream();
                    SecureSocketAdmission.writeFrame(
                            pipelined,
                            new SecurePairingProtocol.Auth("sender-mac", "MacBook Pro", invitation.token)
                                    .encode());
                    LengthPrefixedProtocol.write(pipelined, coalescedFrame);
                    tlsClient.getOutputStream().write(pipelined.toByteArray());
                    tlsClient.getOutputStream().flush();

                    String readyId = SecurePairingProtocol.readyIdentity(
                            SecureSocketAdmission.readFrame(tlsClient.getInputStream()));
                    expect("receiver-android".equals(readyId),
                            "USB AOA TLS handshake must return DWR1 receiver identity");
                    expect(firstConnected.await(3, TimeUnit.SECONDS),
                            "Valid mutual TLS + DWA1 over USB must trigger onConnected");
                    expect("usb".equals(composite.name()),
                            "Composite transport name must switch to 'usb' when AOA session is active");
                    expect(firstPayloadEchoed.await(3, TimeUnit.SECONDS),
                            "Coalesced application frame after DWA1 must be delivered intact");
                    expect(Arrays.equals(coalescedFrame, receivedPayload.get()),
                            "Coalesced frame payload over USB must match byte-for-byte");

                    byte[] echoed = LengthPrefixedProtocol.read(
                            tlsClient.getInputStream(),
                            LengthPrefixedProtocol.LEGACY_MAX_FRAME_BYTES);
                    expect(Arrays.equals(coalescedFrame, echoed),
                            "Composite.send must route outbound length-prefixed frames over USB TLS");

                    long establishedGen = activeGeneration.get();
                    pairing.startPairing();
                    // Unauthorized candidate over USB must be rejected without dropping active session
                    try (SimulatedAccessoryLink rogueLink = new SimulatedAccessoryLink()) {
                        expect(usb.attachStream(
                                "USB 配件",
                                rogueLink.receiverIn,
                                rogueLink.receiverOut,
                                rogueLink.receiverCloseToken()),
                                "Candidate USB stream enters bounded admission");
                        try (SSLSocket rogueTls = rogueLink.openTlsClient(stranger, receiverPin)) {
                            SecureSocketAdmission.writeFrame(
                                    rogueTls.getOutputStream(),
                                    new SecurePairingProtocol.Auth("stranger", "Rogue", new byte[32])
                                            .encode());
                            expect(closed(rogueTls), "Wrong pairing token over USB must close TLS socket");
                        }
                    }
                    expect(admissionRejected.await(3, TimeUnit.SECONDS),
                            "Rejected USB TLS admission must notify listener");
                    expect(connectCount.get() == 1 && activeGeneration.get() == establishedGen,
                            "Rejected USB candidate must never replace active USB session");

                    // Peer revocation must immediately close active USB TLS session
                    pairing.revoke("sender-mac");
                    composite.revokePeer("sender-mac");
                    expect(revokedDisconnect.await(3, TimeUnit.SECONDS),
                            "Revoking paired Mac must disconnect active USB session");
                    expect(closed(tlsClient),
                            "Revoking paired Mac must close underlying USB TLS stream");
                    expect(activeLink.accessoryClosed.get(),
                            "Closing USB session must release accessory file descriptor token");
                }
            }
        } finally {
            composite.stop();
        }
    }

    private static void testExplicitLegacyMode() throws Exception {
        UsbAccessoryReceiverTransport legacyUsb = UsbAccessoryReceiverTransport.legacy();
        expect(!legacyUsb.secure(), "Explicit legacy USB mode must report secure() == false");

        CountDownLatch connected = new CountDownLatch(1);
        CountDownLatch frameReceived = new CountDownLatch(1);
        AtomicReference<byte[]> payloadRef = new AtomicReference<>();

        legacyUsb.start(new ReceiverTransport.Listener() {
            @Override
            public void onListening(int port) {
            }

            @Override
            public void onConnected(long generation, String peer) {
                connected.countDown();
            }

            @Override
            public void onPayload(long generation, byte[] payload) {
                payloadRef.set(payload);
                legacyUsb.send(generation, payload);
                frameReceived.countDown();
            }

            @Override
            public void onDisconnected(long generation) {
            }

            @Override
            public void onError(long generation, String message) {
            }
        });

        try (SimulatedAccessoryLink link = new SimulatedAccessoryLink()) {
            expect(legacyUsb.attachStream(
                    "USB 配件", link.receiverIn, link.receiverOut, link.receiverCloseToken()),
                    "Legacy USB stream should attach when explicitly opted in");
            expect(connected.await(3, TimeUnit.SECONDS), "Legacy USB stream should connect");
            byte[] ping = "{\"type\":\"ping\"}".getBytes(StandardCharsets.UTF_8);
            Socket rawSender = link.senderBridge.serverSocket;
            rawSender.setSoTimeout(4_000);
            LengthPrefixedProtocol.write(rawSender.getOutputStream(), ping);
            expect(frameReceived.await(3, TimeUnit.SECONDS), "Legacy USB frame should arrive");
            expect(Arrays.equals(ping, payloadRef.get()), "Legacy USB payload must match");
            byte[] pong = LengthPrefixedProtocol.read(
                    rawSender.getInputStream(), LengthPrefixedProtocol.LEGACY_MAX_FRAME_BYTES);
            expect(Arrays.equals(ping, pong), "Legacy USB echo must round-trip");
        } finally {
            legacyUsb.stop();
        }
    }

    private static SSLSocket openTcpTlsClient(int port, Identity identity, String serverPin)
            throws Exception {
        SSLSocket tls = (SSLSocket) SecureTls.context(
                identity.pair.getPrivate(), identity.cert, serverPin::equals)
                .getSocketFactory()
                .createSocket("127.0.0.1", port);
        SecureTls.configure(tls, true);
        tls.setSoTimeout(4_000);
        tls.startHandshake();
        return tls;
    }

    private static void testWifiAndUsbBidirectionalHandover() throws Exception {
        Identity receiver = new Identity();
        Identity sender = new Identity();
        String receiverPin = SecureTls.fingerprint(receiver.cert);

        SecurePairingState pairing = new SecurePairingState(
                "receiver-android",
                receiverPin,
                null,
                () -> System.nanoTime() / 1_000_000,
                ignored -> { });
        SecureSocketAdmission security = new SecureSocketAdmission(
                receiver.pair.getPrivate(), receiver.cert, pairing);

        WifiTcpReceiverTransport wifi = new WifiTcpReceiverTransport(0, security, 2_000);
        UsbAccessoryReceiverTransport usb = new UsbAccessoryReceiverTransport(security, 2_000);
        UsbAccessoryReceiverTransport.Composite composite =
                new UsbAccessoryReceiverTransport.Composite(wifi, usb);

        AtomicInteger wifiPort = new AtomicInteger();
        CountDownLatch listening = new CountDownLatch(1);
        AtomicReference<CountDownLatch> connectGate = new AtomicReference<>(new CountDownLatch(1));

        composite.start(new ReceiverTransport.Listener() {
            @Override
            public void onListening(int port) {
                wifiPort.set(port);
                listening.countDown();
            }

            @Override
            public void onConnected(long generation, String peer) {
                connectGate.get().countDown();
            }

            @Override
            public void onPayload(long generation, byte[] payload) {
                composite.send(generation, payload);
            }

            @Override
            public void onDisconnected(long generation) {
            }

            @Override
            public void onError(long generation, String message) {
            }
        });

        try {
            expect(listening.await(3, TimeUnit.SECONDS), "TCP listener must start for handover test");
            SecurePairingProtocol.Invitation invitation = pairing.startPairing();

            // 1. Establish initial Wi-Fi session (pairs sender-mac).
            try (SSLSocket wifiClient1 = openTcpTlsClient(wifiPort.get(), sender, receiverPin)) {
                SecureSocketAdmission.writeFrame(
                        wifiClient1.getOutputStream(),
                        new SecurePairingProtocol.Auth("sender-mac", "MacBook Pro", invitation.token)
                                .encode());
                expect("receiver-android".equals(SecurePairingProtocol.readyIdentity(
                        SecureSocketAdmission.readFrame(wifiClient1.getInputStream()))),
                        "Initial Wi-Fi TLS client must receive DWR1");
                expect(connectGate.get().await(3, TimeUnit.SECONDS),
                        "Initial Wi-Fi TLS client must become active");
                expect("wifi".equals(composite.name()),
                        "Composite name must be 'wifi' while Wi-Fi session is active");

                // 2. Hand over Wi-Fi -> USB AOA: superseded Wi-Fi socket must close cleanly!
                connectGate.set(new CountDownLatch(1));
                try (SimulatedAccessoryLink usbLink = new SimulatedAccessoryLink()) {
                    expect(usb.attachStream(
                            "USB 配件",
                            usbLink.receiverIn,
                            usbLink.receiverOut,
                            usbLink.receiverCloseToken()),
                            "USB AOA stream must attach during Wi-Fi -> USB handover");
                    try (SSLSocket usbClient = usbLink.openTlsClient(sender, receiverPin)) {
                        SecureSocketAdmission.writeFrame(
                                usbClient.getOutputStream(),
                                new SecurePairingProtocol.Auth("sender-mac", "MacBook Pro", null)
                                        .encode());
                        expect("receiver-android".equals(SecurePairingProtocol.readyIdentity(
                                SecureSocketAdmission.readFrame(usbClient.getInputStream()))),
                                "USB AOA reconnect must receive DWR1");
                        expect(connectGate.get().await(3, TimeUnit.SECONDS),
                                "USB AOA session must activate");
                        expect("usb".equals(composite.name()),
                                "Composite name must switch to 'usb' after Wi-Fi -> USB handover");
                        expect(closed(wifiClient1),
                                "Superseded Wi-Fi socket must close cleanly on Wi-Fi -> USB handover");

                        byte[] usbFrame = "{\"transport\":\"usb\"}".getBytes(StandardCharsets.UTF_8);
                        LengthPrefixedProtocol.write(usbClient.getOutputStream(), usbFrame);
                        expect(Arrays.equals(
                                usbFrame,
                                LengthPrefixedProtocol.read(
                                        usbClient.getInputStream(),
                                        LengthPrefixedProtocol.LEGACY_MAX_FRAME_BYTES)),
                                "Active USB session must round-trip frames after superseding Wi-Fi");

                        // 3. Hand over USB AOA -> Wi-Fi: superseded USB socket & accessory token must close cleanly!
                        connectGate.set(new CountDownLatch(1));
                        try (SSLSocket wifiClient2 = openTcpTlsClient(wifiPort.get(), sender, receiverPin)) {
                            SecureSocketAdmission.writeFrame(
                                    wifiClient2.getOutputStream(),
                                    new SecurePairingProtocol.Auth("sender-mac", "MacBook Pro", null)
                                            .encode());
                            expect("receiver-android".equals(SecurePairingProtocol.readyIdentity(
                                    SecureSocketAdmission.readFrame(wifiClient2.getInputStream()))),
                                    "Second Wi-Fi TLS client must receive DWR1");
                            expect(connectGate.get().await(3, TimeUnit.SECONDS),
                                    "Second Wi-Fi TLS session must activate");
                            expect("wifi".equals(composite.name()),
                                    "Composite name must switch back to 'wifi' after USB -> Wi-Fi handover");
                            expect(closed(usbClient),
                                    "Superseded USB TLS socket must close cleanly on USB -> Wi-Fi handover");
                            expect(usbLink.accessoryClosed.get(),
                                    "Superseded USB accessory close token must run on USB -> Wi-Fi handover");

                            byte[] wifiFrame = "{\"transport\":\"wifi2\"}".getBytes(StandardCharsets.UTF_8);
                            LengthPrefixedProtocol.write(wifiClient2.getOutputStream(), wifiFrame);
                            expect(Arrays.equals(
                                    wifiFrame,
                                    LengthPrefixedProtocol.read(
                                            wifiClient2.getInputStream(),
                                            LengthPrefixedProtocol.LEGACY_MAX_FRAME_BYTES)),
                                    "Active Wi-Fi session must round-trip frames after superseding USB");
                        }
                    }
                }
            }
        } finally {
            composite.stop();
        }
    }

    public static void main(String[] args) throws Exception {
        testAccessoryMatching();
        testPacketStreamsAndZlp();
        testMutualTlsAdmissionCompositeAndRevocation();
        testWifiAndUsbBidirectionalHandover();
        testExplicitLegacyMode();
        System.out.println("UsbAccessorySelfTest PASS");
    }
}

/*
 * Copyright (C) 2026 DisplayWeave contributors
 * Adapted from OpenDisplay (https://github.com/OpenDisplay/OpenDisplay,
 * commit e8a7f0f), Copyright (C) OpenDisplay contributors.
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

package app.opendisplay.android;

import android.hardware.usb.UsbAccessory;
import android.hardware.usb.UsbManager;
import android.os.ParcelFileDescriptor;
import android.system.ErrnoException;
import android.system.Os;

import java.io.BufferedInputStream;
import android.annotation.SuppressLint;
import java.io.BufferedOutputStream;
import java.io.Closeable;
import java.io.FileDescriptor;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.net.InetAddress;
import java.net.InetSocketAddress;
import java.net.ServerSocket;
import java.net.Socket;
import java.security.GeneralSecurityException;
import java.security.cert.CertificateExpiredException;
import java.security.cert.CertificateNotYetValidException;
import java.util.HashMap;
import java.util.Locale;
import java.util.Map;
import java.util.Objects;
import java.util.concurrent.ArrayBlockingQueue;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.RejectedExecutionException;
import java.util.concurrent.ScheduledFuture;
import java.util.concurrent.ScheduledThreadPoolExecutor;
import java.util.concurrent.SynchronousQueue;
import java.util.concurrent.ThreadPoolExecutor;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicBoolean;
import java.util.concurrent.atomic.AtomicLong;

import app.opendisplay.android.protocol.LengthPrefixedProtocol;

/**
 * Android Open Accessory (AOA 2.0) wired USB receiver transport.
 *
 * <p>Reads 16 KiB USB bulk URBs with zero-length packet (ZLP) handling via
 * {@link PacketInputStream}, chunks bulk writes to 16 KiB via {@link PacketOutputStream},
 * and bridges the accessory stream across a verified local loopback socket pair so
 * {@link SecureSocketAdmission} enforces the exact same mutual TLS, pairing token
 * verification, certificate pinning, and peer revocation over USB AOA as over TCP.
 */
public final class UsbAccessoryReceiverTransport implements ReceiverTransport {
    public static final String MANUFACTURER = "OpenDisplay";
    public static final String MODEL = "OpenDisplay Receiver";
    static final int PACKET_READ_BYTES = 16 * 1024;
    static final int MAX_EMPTY_READS = 64;
    static final int MAX_CONTROL_BYTES = 64 * 1024;

    private final SecureSocketAdmission security;
    private final int admissionDeadlineMs;
    private final ExecutorService readers = boundedExecutor(2, 2);
    private final ExecutorService writer;
    private final FrameBufferPool framePool;
    private final ExecutorService admissionWorkers = new ThreadPoolExecutor(
            2, 2, 0, TimeUnit.MILLISECONDS,
            new SynchronousQueue<>(), new ThreadPoolExecutor.AbortPolicy());
    private final ScheduledThreadPoolExecutor deadlines = new ScheduledThreadPoolExecutor(1);
    private final Map<Socket, PendingSlot> pending = new HashMap<>();

    private boolean started;
    private volatile boolean running;
    private volatile Listener listener;
    private long nextGeneration;
    private ConnectionContext currentConnection;
    private UsbAccessory attachedAccessory;

    private static final class PendingSlot {
        final LoopbackAccessoryBridge bridge;
        final ScheduledFuture<?> deadline;

        PendingSlot(LoopbackAccessoryBridge bridge, ScheduledFuture<?> deadline) {
            this.bridge = bridge;
            this.deadline = deadline;
        }
    }

    static final class ConnectionContext {
        final long generation;
        final Socket socket;
        final Socket rawSocket;
        final LoopbackAccessoryBridge bridge;
        final SecurePairingState.Peer peer;
        final BufferedInputStream input;
        final BufferedOutputStream output;
        final Object writeLock = new Object();
        final CountDownLatch published = new CountDownLatch(1);
        volatile int maxFrameBytes = LengthPrefixedProtocol.LEGACY_MAX_FRAME_BYTES;

        ConnectionContext(
                long generation,
                Socket socket,
                Socket rawSocket,
                LoopbackAccessoryBridge bridge,
                BufferedInputStream input,
                BufferedOutputStream output,
                SecurePairingState.Peer peer) {
            this.generation = generation;
            this.socket = socket;
            this.rawSocket = rawSocket;
            this.bridge = bridge;
            this.input = input;
            this.output = output;
            this.peer = peer;
        }
    }

    public UsbAccessoryReceiverTransport(SecureSocketAdmission security) {
        this(Objects.requireNonNull(security), 10_000, boundedExecutor(1, 128), new FrameBufferPool());
    }

    UsbAccessoryReceiverTransport(SecureSocketAdmission security, int admissionDeadlineMs) {
        this(Objects.requireNonNull(security), admissionDeadlineMs,
                boundedExecutor(1, 128), new FrameBufferPool());
    }

    /** Plaintext over USB requires explicit legacy compatibility opt-in. */
    public static UsbAccessoryReceiverTransport legacy() {
        return new UsbAccessoryReceiverTransport(
                null, 10_000, boundedExecutor(1, 128), new FrameBufferPool());
    }

    private UsbAccessoryReceiverTransport(
            SecureSocketAdmission security,
            int admissionDeadlineMs,
            ExecutorService writer,
            FrameBufferPool framePool) {
        if (admissionDeadlineMs <= 0 || admissionDeadlineMs > 10_000) {
            throw new IllegalArgumentException("admission deadline");
        }
        this.security = security;
        this.admissionDeadlineMs = admissionDeadlineMs;
        this.writer = writer;
        this.framePool = framePool;
        this.deadlines.setRemoveOnCancelPolicy(true);
    }

    public static boolean isMatchingAccessory(UsbAccessory accessory) {
        return accessory != null
                && isMatchingAccessory(accessory.getManufacturer(), accessory.getModel());
    }

    static boolean isMatchingAccessory(String manufacturer, String model) {
        return MANUFACTURER.equals(manufacturer) && MODEL.equals(model);
    }

    static ThreadPoolExecutor boundedExecutor(int threads, int queueCapacity) {
        return new ThreadPoolExecutor(
                threads, threads, 0, TimeUnit.MILLISECONDS,
                new ArrayBlockingQueue<>(queueCapacity),
                new ThreadPoolExecutor.AbortPolicy());
    }

    @Override
    public String name() {
        return "usb";
    }

    @Override
    public boolean secure() {
        return security != null;
    }

    @Override
    public synchronized void start(Listener nextListener) {
        if (started) {
            return;
        }
        listener = Objects.requireNonNull(nextListener);
        started = true;
        running = true;
    }

    public synchronized boolean isAccessoryAttached(UsbAccessory accessory) {
        return running && accessory != null && accessory.equals(attachedAccessory);
    }

    /**
     * Opens an attached {@link UsbAccessory} if permitted and routes its bulk stream
     * through {@link SecureSocketAdmission} (or explicit legacy mode).
     */
    @SuppressLint("NewApi")
    public boolean openAccessory(UsbManager manager, UsbAccessory accessory) {
        if (manager == null || !isMatchingAccessory(accessory)) {
            return false;
        }
        synchronized (this) {
            if (!running) {
                return false;
            }
            if (accessory.equals(attachedAccessory)) {
                return true;
            }
        }
        if (!manager.hasPermission(accessory)) {
            return false;
        }
        final ParcelFileDescriptor pfd;
        try {
            pfd = manager.openAccessory(accessory);
        } catch (IllegalArgumentException | SecurityException ignored) {
            return false;
        }
        if (pfd == null) {
            return false;
        }
        FileDescriptor rawFd = pfd.getFileDescriptor();
        InputStream in = new PacketInputStream((buf, off, len) -> {
            try {
                return Os.read(rawFd, buf, off, len);
            } catch (ErrnoException error) {
                throw new IOException("USB accessory read failed: " + error.getMessage(), error);
            }
        });
        OutputStream out = new PacketOutputStream(new FileOutputStream(rawFd));
        boolean accepted = attachStream("USB 配件", in, out, pfd, accessory);
        if (!accepted) {
            closeQuietly(pfd);
        }
        return accepted;
    }

    boolean attachStream(
            String peerLabel,
            InputStream accessoryIn,
            OutputStream accessoryOut,
            Closeable accessoryClose) {
        return attachStream(peerLabel, accessoryIn, accessoryOut, accessoryClose, null);
    }

    private boolean attachStream(
            String peerLabel,
            InputStream accessoryIn,
            OutputStream accessoryOut,
            Closeable accessoryClose,
            UsbAccessory accessoryToken) {
        Objects.requireNonNull(accessoryIn, "accessoryIn");
        Objects.requireNonNull(accessoryOut, "accessoryOut");
        synchronized (this) {
            if (!running) {
                closeQuietly(accessoryClose);
                return false;
            }
        }
        final LoopbackAccessoryBridge bridge;
        try {
            bridge = LoopbackAccessoryBridge.open(accessoryIn, accessoryOut, accessoryClose);
        } catch (IOException error) {
            closeQuietly(accessoryClose);
            return false;
        }

        String resolvedPeer = (peerLabel == null || peerLabel.isEmpty()) ? "USB 配件" : peerLabel;
        if (security == null) {
            final BufferedInputStream rawIn;
            final BufferedOutputStream rawOut;
            try {
                rawIn = new BufferedInputStream(bridge.serverSocket.getInputStream());
                rawOut = new BufferedOutputStream(bridge.serverSocket.getOutputStream());
            } catch (IOException | RuntimeException error) {
                bridge.close();
                return false;
            }
            return adopt(
                    bridge.serverSocket,
                    bridge.serverSocket,
                    bridge,
                    rawIn,
                    rawOut,
                    null,
                    resolvedPeer,
                    accessoryToken);
        }
        return beginAdmission(bridge, resolvedPeer, accessoryToken);
    }

    private synchronized boolean beginAdmission(
            LoopbackAccessoryBridge bridge,
            String peerLabel,
            UsbAccessory accessoryToken) {
        Socket raw = bridge.serverSocket;
        if (!running || pending.size() >= 2) {
            if (accessoryToken != null && accessoryToken.equals(attachedAccessory)) {
                attachedAccessory = null;
            }
            bridge.close();
            return false;
        }
        if (accessoryToken != null) {
            attachedAccessory = accessoryToken;
        }
        try {
            ScheduledFuture<?> deadline = deadlines.schedule(
                    () -> expireAdmission(raw),
                    admissionDeadlineMs,
                    TimeUnit.MILLISECONDS);
            pending.put(raw, new PendingSlot(bridge, deadline));
            admissionWorkers.execute(() -> {
                boolean adopted = false;
                try {
                    SecureSocketAdmission.Accepted accepted = security.authenticate(raw);
                    adopted = adopt(
                            raw,
                            accepted.socket,
                            bridge,
                            accepted.input,
                            accepted.output,
                            accepted.peer,
                            peerLabel,
                            accessoryToken);
                } catch (IOException | GeneralSecurityException | RuntimeException error) {
                    String expiry = extractCertificateExpiryMessage(error);
                    String diagnostic = expiry != null
                            ? expiry
                            : (error.getClass().getSimpleName() + ": " + error.getMessage());
                    Listener activeListener = listener;
                    if (running && activeListener != null) {
                        activeListener.onAdmissionRejected(
                                diagnostic.substring(0, Math.min(diagnostic.length(), 512)));
                    }
                } finally {
                    finishAdmission(raw, adopted, accessoryToken);
                }
            });
            return true;
        } catch (RejectedExecutionException error) {
            finishAdmission(raw, false, accessoryToken);
            return false;
        }
    }

    private synchronized void expireAdmission(Socket raw) {
        PendingSlot slot = pending.remove(raw);
        if (slot != null) {
            slot.deadline.cancel(false);
            slot.bridge.close();
        }
    }

    private synchronized void finishAdmission(
            Socket raw, boolean adopted, UsbAccessory accessoryToken) {
        PendingSlot slot = pending.remove(raw);
        if (slot != null) {
            slot.deadline.cancel(false);
            if (!adopted) {
                slot.bridge.close();
            }
        }
        if (!adopted && accessoryToken != null && accessoryToken.equals(attachedAccessory)) {
            attachedAccessory = null;
        }
    }

    private boolean adopt(
            Socket raw,
            Socket socket,
            LoopbackAccessoryBridge bridge,
            BufferedInputStream input,
            BufferedOutputStream output,
            SecurePairingState.Peer peer,
            String peerLabel,
            UsbAccessory accessoryToken) {
        final ConnectionContext context;
        ConnectionContext previous = null;
        Listener activeListener = null;
        boolean rejectedByPool = false;
        synchronized (this) {
            if (!running || (security != null && (!pending.containsKey(raw) || !security.stillTrusted(peer)))) {
                if (accessoryToken != null && accessoryToken.equals(attachedAccessory)) {
                    attachedAccessory = null;
                }
                bridge.close();
                closeSocket(socket);
                return false;
            }
            PendingSlot slot = pending.remove(raw);
            if (slot != null) {
                slot.deadline.cancel(false);
            }
            if (accessoryToken != null) {
                attachedAccessory = accessoryToken;
            }
            context = new ConnectionContext(
                    ++nextGeneration, socket, raw, bridge, input, output, peer);
            try {
                readers.execute(() -> readLoop(context));
                previous = currentConnection;
                currentConnection = context;
                activeListener = listener;
            } catch (RejectedExecutionException error) {
                if (accessoryToken != null && accessoryToken.equals(attachedAccessory)) {
                    attachedAccessory = null;
                }
                rejectedByPool = true;
                previous = null;
                activeListener = listener;
            }
        }
        if (rejectedByPool) {
            bridge.close();
            closeSocket(socket);
            if (activeListener != null) {
                activeListener.onAdmissionRejected("连接切换过于频繁，请稍后重新连接");
            }
            return false;
        }
        closeConnection(previous);
        try {
            if (activeListener != null) {
                activeListener.onConnected(context.generation, peerLabel);
            }
        } finally {
            context.published.countDown();
        }
        return true;
    }

    public void detachAccessory(UsbAccessory accessory) {
        ConnectionContext toClose = null;
        synchronized (this) {
            if (accessory != null && attachedAccessory != null && !accessory.equals(attachedAccessory)) {
                return;
            }
            attachedAccessory = null;
            cancelPendingAdmissions();
            toClose = currentConnection;
            currentConnection = null;
        }
        closeConnection(toClose);
    }

    public synchronized void cancelPendingAdmissions() {
        for (PendingSlot slot : pending.values()) {
            slot.deadline.cancel(false);
            slot.bridge.close();
        }
        pending.clear();
    }

    public void revokePeer(String id) {
        final ConnectionContext revoked;
        final Listener activeListener;
        synchronized (this) {
            cancelPendingAdmissions();
            ConnectionContext active = currentConnection;
            if (active != null && active.peer != null && active.peer.installID.equals(id)) {
                clearCurrent(active);
                attachedAccessory = null;
                revoked = active;
                activeListener = listener;
            } else {
                revoked = null;
                activeListener = null;
            }
        }
        if (revoked != null) {
            closeConnection(revoked);
            if (activeListener != null) {
                activeListener.onDisconnected(revoked.generation);
            }
        }
    }

    @Override
    public void send(long generation, byte[] payload) {
        if (!running || generation <= 0 || payload == null) {
            return;
        }
        ConnectionContext context = current(generation);
        if (context == null) {
            return;
        }
        if (payload.length == 0 || payload.length > MAX_CONTROL_BYTES) {
            disconnectAfterFailure(
                    context, "transportWriteFailure", "控制消息过大，连接已关闭，请重新连接");
            return;
        }
        try {
            writer.execute(() -> {
                try {
                    synchronized (context.writeLock) {
                        if (!isCurrent(context)) {
                            return;
                        }
                        LengthPrefixedProtocol.write(context.output, payload);
                    }
                } catch (IOException error) {
                    disconnectAfterFailure(
                            context,
                            "transportWriteFailure",
                            "USB 发送失败：" + error.getMessage() + "；请检查数据线后重新连接");
                }
            });
        } catch (RejectedExecutionException ignored) {
            if (running) {
                disconnectAfterFailure(
                        context,
                        "transportWriteFailure",
                        "USB 发送队列已满，连接已关闭，请重新插拔或重连");
            }
        }
    }

    @Override
    public void setMaxFrameBytes(long generation, int maximumBytes) {
        ConnectionContext context = current(generation);
        if (context != null) {
            context.maxFrameBytes = LengthPrefixedProtocol.boundedFrameLimit(maximumBytes);
        }
    }

    @Override
    public void stop() {
        stop(null);
    }

    @Override
    public void stop(byte[] finalPayload) {
        synchronized (this) {
            started = true;
            running = false;
            attachedAccessory = null;
            cancelPendingAdmissions();
        }
        clearAndCloseCurrent();
        framePool.close();
        admissionWorkers.shutdownNow();
        deadlines.shutdownNow();
        readers.shutdown();
        writer.shutdownNow();
    }

    private void readLoop(ConnectionContext context) {
        try {
            context.published.await();
            while (running && isCurrent(context) && !context.socket.isClosed()) {
                try (FrameBufferPool.Lease frame = LengthPrefixedProtocol.readPooled(
                        context.input, context.maxFrameBytes, framePool)) {
                    applyNegotiatedFrameLimit(context, frame.bytes(), frame.length);
                    Listener activeListener = listener;
                    if (isCurrent(context) && activeListener != null) {
                        activeListener.onFrame(context.generation, frame);
                    }
                }
            }
        } catch (InterruptedException interrupted) {
            Thread.currentThread().interrupt();
        } catch (LengthPrefixedProtocol.FrameLengthException error) {
            if (running && isCurrent(context) && listener != null) {
                listener.onFrameLengthRejected(
                        context.generation,
                        error.failure.name().toLowerCase(Locale.US),
                        error.frameBytes,
                        error.maximumBytes);
                listener.onError(
                        context.generation,
                        "帧长度被拒绝（" + error.frameBytes + " 字节，限制 "
                                + error.maximumBytes + " 字节，原因 "
                                + error.failure.name().toLowerCase(Locale.US)
                                + "），已关闭当前 USB 连接");
            }
        } catch (IOException | RuntimeException error) {
            if (running && isCurrent(context) && listener != null) {
                listener.onTransportDrop(context.generation, "transportReadFailure");
                listener.onError(context.generation, "USB 连接已断开，等待 Mac 重新连接…");
            }
        } finally {
            boolean wasCurrent = clearCurrent(context);
            closeConnection(context);
            if (context.socket != context.rawSocket) {
                closeSocket(context.socket);
            }
            if (wasCurrent && listener != null) {
                listener.onDisconnected(context.generation);
            }
        }
    }

    private static void applyNegotiatedFrameLimit(
            ConnectionContext context, byte[] payload, int length) {
        if (length <= 0 || length > 32768 || payload[0] != '{') {
            return;
        }
        int negotiatedLimit = LengthPrefixedProtocol.streamConfigFrameLimit(payload, length);
        if (negotiatedLimit > context.maxFrameBytes) {
            context.maxFrameBytes = negotiatedLimit;
        }
    }

    synchronized ConnectionContext current(long generation) {
        return currentConnection != null && currentConnection.generation == generation
                ? currentConnection
                : null;
    }

    private synchronized boolean isCurrent(ConnectionContext candidate) {
        return candidate != null && candidate == currentConnection;
    }

    private synchronized boolean clearCurrent(ConnectionContext candidate) {
        if (candidate == null || candidate != currentConnection) {
            return false;
        }
        currentConnection = null;
        attachedAccessory = null;
        return true;
    }

    private void clearAndCloseCurrent() {
        ConnectionContext active;
        synchronized (this) {
            active = currentConnection;
            currentConnection = null;
            attachedAccessory = null;
        }
        closeConnection(active);
    }

    private void disconnectAfterFailure(
            ConnectionContext context, String reason, String message) {
        if (!clearCurrent(context)) {
            closeConnection(context);
            return;
        }
        closeConnection(context);
        Listener activeListener = listener;
        if (activeListener != null) {
            activeListener.onTransportDrop(context.generation, reason);
            activeListener.onError(context.generation, message);
            activeListener.onDisconnected(context.generation);
        }
    }

    private static void closeConnection(ConnectionContext context) {
        if (context != null) {
            context.bridge.close();
            closeSocket(context.rawSocket);
        }
    }

    private static String extractCertificateExpiryMessage(Throwable error) {
        Throwable cursor = error;
        int depth = 0;
        while (cursor != null && depth++ < 8) {
            if (cursor instanceof CertificateExpiredException
                    || cursor instanceof CertificateNotYetValidException) {
                String msg = cursor.getMessage();
                if (msg != null && !msg.isEmpty()) {
                    return msg;
                }
            }
            cursor = cursor.getCause();
        }
        return null;
    }

    private static void closeSocket(Socket socket) {
        if (socket != null) {
            try {
                socket.close();
            } catch (IOException ignored) {
            }
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

    // MARK: - 16 KiB URB + ZLP Framing Streams

    @FunctionalInterface
    interface PacketReader {
        int read(byte[] buffer, int offset, int length) throws IOException;
    }

    /**
     * Serves arbitrary stream reads from whole 16 KiB bulk USB reads.
     *
     * <p>Android's {@code f_accessory} gadget driver queues 16 KiB USB requests; reading
     * smaller buffers can drop the remainder of a transfer. A single 0-byte read is a
     * USB zero-length packet (ZLP) terminating a packet-aligned transfer rather than EOF;
     * consecutive empty reads are bounded to {@link #MAX_EMPTY_READS}.
     */
    static final class PacketInputStream extends InputStream {
        private final PacketReader reader;
        private final byte[] buffer = new byte[PACKET_READ_BYTES];
        private int position;
        private int limit;

        PacketInputStream(PacketReader reader) {
            this.reader = Objects.requireNonNull(reader, "reader");
        }

        @Override
        public int read() throws IOException {
            if (!fill()) {
                return -1;
            }
            return buffer[position++] & 0xFF;
        }

        @Override
        public int read(byte[] target, int offset, int length) throws IOException {
            Objects.checkFromIndexSize(offset, length, target.length);
            if (length == 0) {
                return 0;
            }
            if (!fill()) {
                return -1;
            }
            int count = Math.min(length, limit - position);
            System.arraycopy(buffer, position, target, offset, count);
            position += count;
            return count;
        }

        @Override
        public int available() {
            return limit - position;
        }

        private boolean fill() throws IOException {
            if (position < limit) {
                return true;
            }
            int emptyReads = 0;
            while (true) {
                int readBytes = reader.read(buffer, 0, PACKET_READ_BYTES);
                if (readBytes < 0) {
                    return false;
                }
                if (readBytes > 0) {
                    position = 0;
                    limit = readBytes;
                    return true;
                }
                if (++emptyReads >= MAX_EMPTY_READS) {
                    return false;
                }
            }
        }
    }

    /** Chunks outbound writes to {@code <= 16 KiB} to match {@code f_accessory} URB limits. */
    static final class PacketOutputStream extends OutputStream {
        private final OutputStream delegate;

        PacketOutputStream(OutputStream delegate) {
            this.delegate = Objects.requireNonNull(delegate, "delegate");
        }

        @Override
        public void write(int oneByte) throws IOException {
            delegate.write(oneByte);
        }

        @Override
        public void write(byte[] buffer, int offset, int length) throws IOException {
            Objects.checkFromIndexSize(offset, length, buffer.length);
            int cursor = offset;
            int remaining = length;
            while (remaining > 0) {
                int chunk = Math.min(remaining, PACKET_READ_BYTES);
                delegate.write(buffer, cursor, chunk);
                cursor += chunk;
                remaining -= chunk;
            }
        }

        @Override
        public void flush() throws IOException {
            delegate.flush();
        }

        @Override
        public void close() throws IOException {
            delegate.close();
        }
    }

    // MARK: - Verified Local Loopback Socket Bridge

    static final class LoopbackAccessoryBridge implements Closeable {
        final Socket serverSocket;
        private final Socket bridgeSocket;
        private final InputStream accessoryIn;
        private final OutputStream accessoryOut;
        private final Closeable accessoryClose;
        private final AtomicBoolean closed = new AtomicBoolean(false);

        private LoopbackAccessoryBridge(
                Socket serverSocket,
                Socket bridgeSocket,
                InputStream accessoryIn,
                OutputStream accessoryOut,
                Closeable accessoryClose) {
            this.serverSocket = serverSocket;
            this.bridgeSocket = bridgeSocket;
            this.accessoryIn = accessoryIn;
            this.accessoryOut = accessoryOut;
            this.accessoryClose = accessoryClose;
        }

        static LoopbackAccessoryBridge open(
                InputStream accessoryIn,
                OutputStream accessoryOut,
                Closeable accessoryClose) throws IOException {
            InetAddress loopback = InetAddress.getByName("127.0.0.1");
            Socket accepted = null;
            Socket client = null;
            try (ServerSocket pairListener = new ServerSocket()) {
                pairListener.setSoTimeout(2_000);
                pairListener.bind(new InetSocketAddress(loopback, 0), 1);
                client = new Socket();
                client.setTcpNoDelay(true);
                client.connect(new InetSocketAddress(loopback, pairListener.getLocalPort()), 2_000);
                accepted = pairListener.accept();
                accepted.setTcpNoDelay(true);
                if (!Objects.equals(accepted.getRemoteSocketAddress(), client.getLocalSocketAddress())) {
                    throw new IOException("loopback socket pair endpoint mismatch");
                }
            } catch (IOException | RuntimeException error) {
                closeSocket(accepted);
                closeSocket(client);
                throw error;
            }

            LoopbackAccessoryBridge bridge = new LoopbackAccessoryBridge(
                    accepted, client, accessoryIn, accessoryOut, accessoryClose);
            bridge.startPumps();
            return bridge;
        }

        private void startPumps() {
            Thread inbound = new Thread(this::pumpAccessoryToSocket, "displayweave-aoa-in");
            inbound.setDaemon(true);
            Thread outbound = new Thread(this::pumpSocketToAccessory, "displayweave-aoa-out");
            outbound.setDaemon(true);
            inbound.start();
            outbound.start();
        }

        private void pumpAccessoryToSocket() {
            byte[] buf = new byte[PACKET_READ_BYTES];
            try {
                OutputStream socketOut = bridgeSocket.getOutputStream();
                int count;
                while (!closed.get() && (count = accessoryIn.read(buf)) >= 0) {
                    if (count == 0) {
                        continue;
                    }
                    socketOut.write(buf, 0, count);
                    socketOut.flush();
                }
                if (!bridgeSocket.isClosed()) {
                    try {
                        bridgeSocket.shutdownOutput();
                    } catch (IOException ignored) {
                    }
                }
            } catch (IOException ignored) {
                close();
            }
        }

        private void pumpSocketToAccessory() {
            byte[] buf = new byte[PACKET_READ_BYTES];
            try {
                InputStream socketIn = bridgeSocket.getInputStream();
                int count;
                while (!closed.get() && (count = socketIn.read(buf)) >= 0) {
                    if (count == 0) {
                        continue;
                    }
                    accessoryOut.write(buf, 0, count);
                    accessoryOut.flush();
                }
            } catch (IOException ignored) {
            } finally {
                close();
            }
        }

        @Override
        public void close() {
            if (!closed.compareAndSet(false, true)) {
                return;
            }
            closeQuietly(accessoryClose);
            closeQuietly(accessoryIn);
            closeQuietly(accessoryOut);
            closeSocket(bridgeSocket);
            closeSocket(serverSocket);
        }
    }

    // MARK: - Dual Transport Multiplexer (TCP/ADB/Wi-Fi + USB AOA)

    /**
     * Multiplexes {@link WifiTcpReceiverTransport} (port 9000 Wi-Fi &amp; ADB forward)
     * and {@link UsbAccessoryReceiverTransport} behind one {@link ReceiverTransport}
     * with a single monotonic generation counter.
     */
    static final class Composite implements ReceiverTransport {
        final WifiTcpReceiverTransport wifi;
        final UsbAccessoryReceiverTransport usb;
        private final AtomicLong nextServerGeneration = new AtomicLong();
        private volatile Route activeRoute;

        private static final class Route {
            final long serverGeneration;
            final ReceiverTransport transport;
            final long childGeneration;

            Route(long serverGeneration, ReceiverTransport transport, long childGeneration) {
                this.serverGeneration = serverGeneration;
                this.transport = transport;
                this.childGeneration = childGeneration;
            }
        }

        Composite(WifiTcpReceiverTransport wifi, UsbAccessoryReceiverTransport usb) {
            this.wifi = Objects.requireNonNull(wifi, "wifi");
            this.usb = Objects.requireNonNull(usb, "usb");
        }

        @Override
        public void start(Listener listener) {
            Objects.requireNonNull(listener, "listener");
            wifi.start(wrap(wifi, listener));
            usb.start(wrap(usb, listener));
        }

        @Override
        public void stop() {
            stop(null);
        }

        @Override
        public void stop(byte[] finalPayload) {
            activeRoute = null;
            usb.stop(finalPayload);
            wifi.stop(finalPayload);
        }

        @Override
        public void send(long generation, byte[] payload) {
            Route route = activeRoute;
            if (route != null && route.serverGeneration == generation) {
                route.transport.send(route.childGeneration, payload);
            }
        }

        @Override
        public void setMaxFrameBytes(long generation, int maximumBytes) {
            Route route = activeRoute;
            if (route != null && route.serverGeneration == generation) {
                route.transport.setMaxFrameBytes(route.childGeneration, maximumBytes);
            }
        }

        @Override
        public String name() {
            Route route = activeRoute;
            return route != null ? route.transport.name() : wifi.name();
        }

        @Override
        public boolean secure() {
            return wifi.secure() && usb.secure();
        }

        void cancelPendingAdmissions() {
            wifi.cancelPendingAdmissions();
            usb.cancelPendingAdmissions();
        }

        void revokePeer(String id) {
            wifi.revokePeer(id);
            usb.revokePeer(id);
        }

        private long activate(ReceiverTransport child, long childGeneration) {
            final Route previous;
            final long serverGen;
            synchronized (this) {
                previous = activeRoute;
                serverGen = nextServerGeneration.incrementAndGet();
                activeRoute = new Route(serverGen, child, childGeneration);
            }
            if (previous != null && previous.transport != child) {
                if (previous.transport == usb) {
                    usb.detachAccessory(null);
                } else if (previous.transport == wifi) {
                    wifi.disconnectCurrent();
                }
            }
            return serverGen;
        }

        private synchronized long mappedGeneration(ReceiverTransport child, long childGeneration) {
            Route route = activeRoute;
            if (route != null && route.transport == child && route.childGeneration == childGeneration) {
                return route.serverGeneration;
            }
            return 0;
        }

        private Listener wrap(ReceiverTransport child, Listener downstream) {
            return new Listener() {
                @Override
                public void onListening(int port) {
                    downstream.onListening(port);
                }

                @Override
                public void onListenerError(String message) {
                    downstream.onListenerError(message);
                }

                @Override
                public void onAdmissionRejected(String diagnostic) {
                    downstream.onAdmissionRejected(diagnostic);
                }

                @Override
                public void onConnected(long childGen, String peer) {
                    long serverGen = activate(child, childGen);
                    downstream.onConnected(serverGen, peer);
                }

                @Override
                public void onPayload(long childGen, byte[] payload) {
                    long serverGen = mappedGeneration(child, childGen);
                    if (serverGen > 0) {
                        downstream.onPayload(serverGen, payload);
                    }
                }

                @Override
                public void onFrame(long childGen, FrameBufferPool.Lease frame) {
                    long serverGen = mappedGeneration(child, childGen);
                    if (serverGen > 0) {
                        downstream.onFrame(serverGen, frame);
                    }
                }

                @Override
                public void onFrameLengthRejected(
                        long childGen, String reason, int frameBytes, int maximumBytes) {
                    long serverGen = mappedGeneration(child, childGen);
                    if (serverGen > 0) {
                        downstream.onFrameLengthRejected(serverGen, reason, frameBytes, maximumBytes);
                    }
                }

                @Override
                public void onTransportDrop(long childGen, String reason) {
                    long serverGen = mappedGeneration(child, childGen);
                    if (serverGen > 0) {
                        downstream.onTransportDrop(serverGen, reason);
                    }
                }

                @Override
                public void onDisconnected(long childGen) {
                    long serverGen = mappedGeneration(child, childGen);
                    if (serverGen > 0) {
                        downstream.onDisconnected(serverGen);
                    }
                }

                @Override
                public void onError(long childGen, String message) {
                    long serverGen = mappedGeneration(child, childGen);
                    if (serverGen > 0) {
                        downstream.onError(serverGen, message);
                    }
                }
            };
        }
    }
}

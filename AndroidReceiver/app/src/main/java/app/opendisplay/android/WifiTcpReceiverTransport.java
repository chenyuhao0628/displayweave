package app.opendisplay.android;

import java.io.BufferedInputStream;
import java.io.BufferedOutputStream;
import java.io.IOException;
import java.net.InetSocketAddress;
import java.net.BindException;
import java.net.ServerSocket;
import java.net.Socket;
import java.util.Locale;
import java.util.HashMap;
import java.util.Map;
import java.util.concurrent.ScheduledThreadPoolExecutor;
import java.util.concurrent.ScheduledFuture;
import java.util.concurrent.SynchronousQueue;
import java.util.concurrent.ArrayBlockingQueue;
import java.util.concurrent.ThreadPoolExecutor;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.RejectedExecutionException;

import app.opendisplay.android.protocol.LengthPrefixedProtocol;

public final class WifiTcpReceiverTransport implements ReceiverTransport {
    static final int MAX_CONTROL_BYTES = 64 * 1024;
    private static final int BIND_ATTEMPTS = 6;
    private static final int BIND_RETRY_MS = 50;
    private final int requestedPort;
    private final ExecutorService acceptor = Executors.newSingleThreadExecutor();
    private final ExecutorService readers = boundedExecutor(2, 2);
    private final ExecutorService writer;
    private final FrameBufferPool framePool;
    private final SecureSocketAdmission security;
    private final int admissionDeadlineMs;
    private final ExecutorService admissionWorkers = new ThreadPoolExecutor(2, 2, 0, TimeUnit.MILLISECONDS,
            new SynchronousQueue<>(), new ThreadPoolExecutor.AbortPolicy());
    private final ScheduledThreadPoolExecutor deadlines = new ScheduledThreadPoolExecutor(1);
    private final Map<Socket, ScheduledFuture<?>> pending = new HashMap<>();
    private boolean started;
    private volatile boolean running;
    private Listener listener;
    private volatile ServerSocket serverSocket;
    private long nextGeneration;
    private ConnectionContext currentConnection;

    static final class ConnectionContext {
        final long generation;
        final Socket socket;
        final Socket rawSocket;
        final SecurePairingState.Peer peer;
        final BufferedInputStream input;
        final BufferedOutputStream output;
        final Object writeLock = new Object();
        final long connectedAtMs;
        volatile long lastPayloadAtMs;
        volatile int maxFrameBytes = LengthPrefixedProtocol.LEGACY_MAX_FRAME_BYTES;

        ConnectionContext(long generation, Socket socket,
                          BufferedInputStream input, BufferedOutputStream output,
                          long connectedAtMs, Socket rawSocket, SecurePairingState.Peer peer) {
            this.generation = generation;
            this.socket = socket;
            this.rawSocket = rawSocket;
            this.peer = peer;
            this.input = input;
            this.output = output;
            this.connectedAtMs = connectedAtMs;
            lastPayloadAtMs = connectedAtMs;
        }
    }

    public WifiTcpReceiverTransport(int port, SecureSocketAdmission security) {
        this(port, java.util.Objects.requireNonNull(security), 10000);
    }

    WifiTcpReceiverTransport(int port, SecureSocketAdmission security, int deadlineMs) {
        this(port, java.util.Objects.requireNonNull(security), deadlineMs,
                boundedExecutor(1, 128), new FrameBufferPool());
    }

    /** Plaintext requires an explicit local compatibility choice. */
    public static WifiTcpReceiverTransport legacy(int port) {
        return legacy(port, boundedExecutor(1, 128), new FrameBufferPool());
    }

    static WifiTcpReceiverTransport legacy(int port, ExecutorService writer) {
        return legacy(port, writer, new FrameBufferPool());
    }

    static WifiTcpReceiverTransport legacy(int port, ExecutorService writer, FrameBufferPool pool) {
        return new WifiTcpReceiverTransport(port, null, 10000, writer, pool);
    }

    private WifiTcpReceiverTransport(int port, SecureSocketAdmission security, int deadlineMs,
                                     ExecutorService writer, FrameBufferPool framePool) {
        if (deadlineMs <= 0 || deadlineMs > 10000) throw new IllegalArgumentException("admission deadline");
        requestedPort = port;
        this.security = security;
        this.admissionDeadlineMs = deadlineMs;
        this.writer = writer;
        this.framePool = framePool;
        deadlines.setRemoveOnCancelPolicy(true);
    }

    @Override public boolean secure() { return security != null; }

    static ThreadPoolExecutor boundedExecutor(int threads, int queueCapacity) {
        return new ThreadPoolExecutor(threads, threads, 0, TimeUnit.MILLISECONDS,
                new ArrayBlockingQueue<>(queueCapacity), new ThreadPoolExecutor.AbortPolicy());
    }

    @Override
    public String name() {
        return "wifi";
    }

    @Override
    public synchronized void start(Listener nextListener) {
        if (started) {
            return;
        }
        listener = java.util.Objects.requireNonNull(nextListener);
        started = true;
        running = true;
        acceptor.execute(this::acceptLoop);
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
            disconnectAfterFailure(context, "transportWriteFailure", "控制消息过大，连接已关闭，请重新连接");
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
                    disconnectAfterFailure(context, "transportWriteFailure",
                            "发送失败：" + error.getMessage());
                }
            });
        } catch (RejectedExecutionException ignored) {
            // A blocked peer must not accumulate unlimited input, or lose only an
            // individual button-up. Closing the session resets the full input state.
            if (running) {
                disconnectAfterFailure(context, "transportWriteFailure",
                        "发送队列已满，连接已关闭，请检查网络后重新连接");
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
            cancelPendingAdmissions();
        }
        // Lifecycle callbacks invoke stop() on Android's main thread. A best-effort
        // goodbye must never turn that path into blocking network I/O; closing the
        // socket is already the protocol's authoritative disconnect signal.
        clearAndCloseCurrent();
        framePool.close();
        ServerSocket activeServer = serverSocket;
        if (activeServer != null) {
            try {
                activeServer.close();
            } catch (IOException ignored) {
            }
        }
        admissionWorkers.shutdownNow();
        deadlines.shutdownNow();
        acceptor.shutdownNow();
        // Each admitted reader owns its TLS wrapper's final close. Raw sockets
        // are already closed; drain the bounded queue so no wrapper is orphaned.
        readers.shutdown();
        writer.shutdownNow();
    }

    private void acceptLoop() {
        for (int attempt = 0; running && attempt < BIND_ATTEMPTS; attempt++) {
            boolean bound = false;
            try (ServerSocket server = new ServerSocket()) {
                server.setReuseAddress(true);
                synchronized (this) {
                    if (!running) return;
                    // Give stop() ownership even before bind completes.
                    serverSocket = server;
                }
                server.bind(new InetSocketAddress(requestedPort));
                bound = true;
                synchronized (this) {
                    if (!running) return;
                    listener.onListening(server.getLocalPort());
                }
                while (running) {
                    Socket accepted = server.accept();
                    try {
                        configureAcceptedSocket(accepted);
                        if (security == null) {
                            adopt(accepted, accepted, new BufferedInputStream(accepted.getInputStream()),
                                    new BufferedOutputStream(accepted.getOutputStream()), null);
                        } else {
                            beginAdmission(accepted);
                        }
                    } catch (IOException | RuntimeException error) {
                        closeSocket(accepted);
                    }
                }
                return;
            } catch (IOException error) {
                if (!running) return;
                // Android can retain the old port briefly while a closed
                // accept() unwinds during a security-mode switch. Retry only
                // initial bind conflicts, off the UI thread, for at most 250 ms.
                if (!bound && error instanceof BindException && attempt + 1 < BIND_ATTEMPTS) {
                    try { Thread.sleep(BIND_RETRY_MS); }
                    catch (InterruptedException stopped) { Thread.currentThread().interrupt(); return; }
                    continue;
                }
                synchronized (this) {
                    if (running) listener.onListenerError("监听失败，请检查端口占用后重新打开接收：" + error.getMessage());
                }
                return;
            }
        }
    }

    private synchronized void beginAdmission(Socket raw) {
        if (!running || pending.size() >= 2) { closeSocket(raw); return; }
        try {
            ScheduledFuture<?> deadline = deadlines.schedule(() -> expireAdmission(raw),
                    admissionDeadlineMs, TimeUnit.MILLISECONDS);
            pending.put(raw, deadline);
            admissionWorkers.execute(() -> {
                try {
                    SecureSocketAdmission.Accepted accepted = security.authenticate(raw);
                    adopt(raw, accepted.socket, accepted.input, accepted.output, accepted.peer);
                } catch (IOException | java.security.GeneralSecurityException | RuntimeException error) {
                    String diagnostic = error.getClass().getSimpleName() + ": " + error.getMessage();
                    if (running) listener.onAdmissionRejected(diagnostic.substring(0, Math.min(diagnostic.length(), 512)));
                    // A rejected candidate is not an application session. It must
                    // neither replace the active peer nor mutate its UI state.
                } finally {
                    finishAdmission(raw);
                }
            });
        } catch (RejectedExecutionException error) {
            finishAdmission(raw);
        }
    }

    private synchronized void expireAdmission(Socket raw) {
        ScheduledFuture<?> deadline = pending.remove(raw);
        if (deadline != null) { deadline.cancel(false); closeSocket(raw); }
    }

    private synchronized void finishAdmission(Socket raw) {
        ScheduledFuture<?> deadline = pending.remove(raw);
        if (deadline != null) { deadline.cancel(false); closeSocket(raw); }
    }

    /** The transport lock orders adoption, revocation and lifecycle shutdown. */
    private synchronized void adopt(Socket raw, Socket socket, BufferedInputStream input,
                                     BufferedOutputStream output, SecurePairingState.Peer peer) {
        if (!running || (security != null && (!pending.containsKey(raw) || !security.stillTrusted(peer)))) {
            closeSocket(raw); closeSocket(socket); return;
        }
        ScheduledFuture<?> deadline = pending.remove(raw);
        if (deadline != null) deadline.cancel(false);
        ConnectionContext context = new ConnectionContext(++nextGeneration, socket, input, output,
                System.currentTimeMillis(), raw, peer);
        try {
            // The worker cannot pass isCurrent until this lock is released.
            // Guarantee a cleanup owner before publishing the connection.
            readers.execute(() -> readLoop(context));
        } catch (RejectedExecutionException error) {
            closeSocket(raw); closeSocket(socket); // admission/accept worker only
            listener.onAdmissionRejected("连接切换过于频繁，请稍后重新连接");
            return;
        }
        ConnectionContext previous = currentConnection;
        currentConnection = context;
        closeConnection(previous);
        listener.onConnected(context.generation, raw.getInetAddress().getHostAddress());
    }

    synchronized int pendingAdmissionCount() { return pending.size(); }

    public synchronized void cancelPendingAdmissions() {
        for (Map.Entry<Socket, ScheduledFuture<?>> entry : pending.entrySet()) {
            entry.getValue().cancel(false); closeSocket(entry.getKey());
        }
        pending.clear();
    }

    public synchronized void revokePeer(String id) {
        cancelPendingAdmissions();
        ConnectionContext active = currentConnection;
        if (active != null && active.peer != null && active.peer.installID.equals(id)) {
            clearCurrent(active); closeConnection(active);
            listener.onDisconnected(active.generation);
        }
    }

    private void readLoop(ConnectionContext context) {
        try {
            while (running && isCurrent(context) && !context.socket.isClosed()) {
                try (FrameBufferPool.Lease frame = LengthPrefixedProtocol.readPooled(
                        context.input, context.maxFrameBytes, framePool)) {
                    context.lastPayloadAtMs = System.currentTimeMillis();
                    applyNegotiatedFrameLimit(context, frame.bytes(), frame.length);
                    if (isCurrent(context)) {
                        listener.onFrame(context.generation, frame);
                    }
                }
            }
        } catch (LengthPrefixedProtocol.FrameLengthException error) {
            if (running && isCurrent(context)) {
                listener.onFrameLengthRejected(
                        context.generation,
                        error.failure.name().toLowerCase(Locale.US),
                        error.frameBytes,
                        error.maximumBytes);
                listener.onError(context.generation,
                        "帧长度被拒绝（" + error.frameBytes + " 字节，限制 "
                                + error.maximumBytes + " 字节，原因 "
                                + error.failure.name().toLowerCase(Locale.US)
                                + "），已关闭当前连接并等待有限恢复");
            }
        } catch (IOException | RuntimeException error) {
            if (running && isCurrent(context)) {
                listener.onTransportDrop(
                        context.generation, "transportReadFailure");
                listener.onError(context.generation,
                        "连接已断开，等待 Mac 重新连接…");
            }
        } finally {
            boolean wasCurrent = clearCurrent(context);
            closeConnection(context);
            // Conscrypt's TLS close can write close_notify even when the raw
            // socket is closed. Keep it on this owned reader, never Android UI.
            if (context.socket != context.rawSocket) closeSocket(context.socket);
            if (wasCurrent) {
                listener.onDisconnected(context.generation);
            }
        }
    }

    static void configureAcceptedSocket(Socket socket) throws IOException {
        socket.setTcpNoDelay(true);
        socket.setKeepAlive(true);
    }

    private static void applyNegotiatedFrameLimit(
            ConnectionContext context, byte[] payload, int length) {
        int negotiatedLimit = LengthPrefixedProtocol.streamConfigFrameLimit(payload, length);
        if (negotiatedLimit > 0) {
            context.maxFrameBytes = negotiatedLimit;
        }
    }

    synchronized long currentGeneration() {
        return currentConnection == null ? 0 : currentConnection.generation;
    }

    private synchronized ConnectionContext current() {
        return currentConnection;
    }

    private synchronized ConnectionContext current(long generation) {
        return currentConnection != null && currentConnection.generation == generation
                ? currentConnection : null;
    }

    private synchronized boolean isCurrent(ConnectionContext candidate) {
        return candidate != null && candidate == currentConnection;
    }

    private synchronized boolean clearCurrent(ConnectionContext candidate) {
        if (candidate == null || candidate != currentConnection) {
            return false;
        }
        currentConnection = null;
        return true;
    }

    private void clearAndCloseCurrent() {
        ConnectionContext active;
        synchronized (this) {
            active = currentConnection;
            currentConnection = null;
        }
        closeConnection(active);
    }

    private void disconnectAfterFailure(ConnectionContext context, String reason, String message) {
        if (!clearCurrent(context)) {
            closeConnection(context);
            return;
        }
        closeConnection(context);
        Listener activeListener = listener;
        if (activeListener != null) {
            activeListener.onTransportDrop(
                    context.generation, reason);
            activeListener.onError(context.generation, message);
            activeListener.onDisconnected(context.generation);
        }
    }

    private static void closeConnection(ConnectionContext context) {
        if (context != null) {
            closeSocket(context.rawSocket);
        }
    }

    private static void closeSocket(Socket socket) {
        if (socket != null) {
            try {
                socket.close();
            } catch (IOException ignored) {
            }
        }
    }
}

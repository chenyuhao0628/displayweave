package app.opendisplay.android;

import java.io.BufferedInputStream;
import java.io.BufferedOutputStream;
import java.io.IOException;
import java.net.InetSocketAddress;
import java.net.ServerSocket;
import java.net.Socket;
import java.util.Locale;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.RejectedExecutionException;

import app.opendisplay.android.protocol.LengthPrefixedProtocol;

public final class WifiTcpReceiverTransport implements ReceiverTransport {
    private final int requestedPort;
    private final ExecutorService acceptor = Executors.newSingleThreadExecutor();
    private final ExecutorService readers = Executors.newCachedThreadPool();
    private final ExecutorService writer = Executors.newSingleThreadExecutor();
    private volatile boolean running;
    private Listener listener;
    private volatile ServerSocket serverSocket;
    private long nextGeneration;
    private ConnectionContext currentConnection;

    static final class ConnectionContext {
        final long generation;
        final Socket socket;
        final BufferedInputStream input;
        final BufferedOutputStream output;
        final Object writeLock = new Object();
        final long connectedAtMs;
        volatile long lastPayloadAtMs;
        volatile int maxFrameBytes = LengthPrefixedProtocol.LEGACY_MAX_FRAME_BYTES;

        ConnectionContext(long generation, Socket socket,
                          BufferedInputStream input, BufferedOutputStream output,
                          long connectedAtMs) {
            this.generation = generation;
            this.socket = socket;
            this.input = input;
            this.output = output;
            this.connectedAtMs = connectedAtMs;
            lastPayloadAtMs = connectedAtMs;
        }
    }

    public WifiTcpReceiverTransport(int port) {
        requestedPort = port;
    }

    @Override
    public String name() {
        return "wifi";
    }

    @Override
    public void start(Listener nextListener) {
        if (running) {
            return;
        }
        listener = nextListener;
        running = true;
        acceptor.execute(this::acceptLoop);
    }

    @Override
    public void send(long generation, byte[] payload) {
        if (!running || generation <= 0 || payload == null) {
            return;
        }
        try {
            writer.execute(() -> {
                ConnectionContext context = current(generation);
                if (context == null) {
                    return;
                }
                try {
                    synchronized (context.writeLock) {
                        if (!isCurrent(context)) {
                            return;
                        }
                        LengthPrefixedProtocol.write(context.output, payload);
                    }
                } catch (IOException error) {
                    disconnectAfterWriteFailure(context,
                            "发送失败：" + error.getMessage());
                }
            });
        } catch (RejectedExecutionException ignored) {
            // stop() may race with a final timer/control send.
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
        running = false;
        ConnectionContext active = current();
        if (finalPayload != null && active != null) {
            try {
                synchronized (active.writeLock) {
                    if (isCurrent(active)) {
                        LengthPrefixedProtocol.write(active.output, finalPayload);
                    }
                }
            } catch (IOException ignored) {
            }
        }
        clearAndCloseCurrent();
        ServerSocket activeServer = serverSocket;
        if (activeServer != null) {
            try {
                activeServer.close();
            } catch (IOException ignored) {
            }
        }
        acceptor.shutdownNow();
        readers.shutdownNow();
        writer.shutdownNow();
    }

    private void acceptLoop() {
        try (ServerSocket server = new ServerSocket()) {
            server.setReuseAddress(true);
            server.bind(new InetSocketAddress(requestedPort));
            serverSocket = server;
            listener.onListening(server.getLocalPort());
            while (running) {
                Socket accepted = server.accept();
                configureAcceptedSocket(accepted);
                ConnectionContext context;
                ConnectionContext previous;
                synchronized (this) {
                    if (!running) {
                        closeSocket(accepted);
                        break;
                    }
                    context = new ConnectionContext(
                            ++nextGeneration,
                            accepted,
                            new BufferedInputStream(accepted.getInputStream()),
                            new BufferedOutputStream(accepted.getOutputStream()),
                            System.currentTimeMillis());
                    previous = currentConnection;
                    currentConnection = context;
                }
                closeConnection(previous);
                listener.onConnected(
                        context.generation, accepted.getInetAddress().getHostAddress());
                readers.execute(() -> readLoop(context));
            }
        } catch (IOException error) {
            if (running) {
                Listener activeListener = listener;
                ConnectionContext active = current();
                if (activeListener != null && active != null) {
                    activeListener.onError(active.generation,
                            "监听失败：" + error.getMessage());
                }
            }
        }
    }

    private void readLoop(ConnectionContext context) {
        try {
            while (running && isCurrent(context) && !context.socket.isClosed()) {
                byte[] payload = LengthPrefixedProtocol.read(
                        context.input,
                        context.maxFrameBytes);
                context.lastPayloadAtMs = System.currentTimeMillis();
                applyNegotiatedFrameLimit(context, payload);
                if (isCurrent(context)) {
                    listener.onPayload(context.generation, payload);
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
        } catch (IOException error) {
            if (running && isCurrent(context)) {
                listener.onError(context.generation,
                        "连接已断开，等待 Mac 重新连接…");
            }
        } finally {
            boolean wasCurrent = clearCurrent(context);
            closeConnection(context);
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
            ConnectionContext context, byte[] payload) {
        int negotiatedLimit = LengthPrefixedProtocol.streamConfigFrameLimit(payload);
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

    private void disconnectAfterWriteFailure(ConnectionContext context, String message) {
        if (!clearCurrent(context)) {
            closeConnection(context);
            return;
        }
        closeConnection(context);
        Listener activeListener = listener;
        if (activeListener != null) {
            activeListener.onError(context.generation, message);
            activeListener.onDisconnected(context.generation);
        }
    }

    private static void closeConnection(ConnectionContext context) {
        if (context != null) {
            closeSocket(context.socket);
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

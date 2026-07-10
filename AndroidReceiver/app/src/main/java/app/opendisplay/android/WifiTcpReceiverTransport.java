package app.opendisplay.android;

import java.io.BufferedInputStream;
import java.io.BufferedOutputStream;
import java.io.IOException;
import java.net.InetSocketAddress;
import java.net.ServerSocket;
import java.net.Socket;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.RejectedExecutionException;

import app.opendisplay.android.protocol.LengthPrefixedProtocol;

public final class WifiTcpReceiverTransport implements ReceiverTransport {
    private final int requestedPort;
    private final ExecutorService reader = Executors.newSingleThreadExecutor();
    private final ExecutorService writer = Executors.newSingleThreadExecutor();
    private volatile boolean running;
    private Listener listener;
    private ServerSocket serverSocket;
    private Socket socket;
    private BufferedOutputStream output;

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
        reader.execute(this::acceptLoop);
    }

    @Override
    public void send(byte[] payload) {
        if (!running) {
            return;
        }
        try {
            writer.execute(() -> {
                BufferedOutputStream activeOutput;
                synchronized (this) {
                    activeOutput = output;
                }
                if (activeOutput == null) {
                    return;
                }
                try {
                    LengthPrefixedProtocol.write(activeOutput, payload);
                    activeOutput.flush();
                } catch (IOException error) {
                    notifyError("发送失败：" + error.getMessage());
                }
            });
        } catch (RejectedExecutionException ignored) {
            // stop() may race with a final timer/control send.
        }
    }

    @Override
    public void stop() {
        running = false;
        closeClient();
        ServerSocket activeServer = serverSocket;
        if (activeServer != null) {
            try {
                activeServer.close();
            } catch (IOException ignored) {
            }
        }
        reader.shutdownNow();
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
                accepted.setTcpNoDelay(true);
                closeClient();
                synchronized (this) {
                    socket = accepted;
                    output = new BufferedOutputStream(accepted.getOutputStream());
                }
                listener.onConnected(accepted.getInetAddress().getHostAddress());
                readLoop(accepted);
            }
        } catch (IOException error) {
            if (running) {
                notifyError("监听失败：" + error.getMessage());
            }
        }
    }

    private void readLoop(Socket active) {
        try {
            BufferedInputStream input = new BufferedInputStream(active.getInputStream());
            while (running && isActive(active) && !active.isClosed()) {
                listener.onPayload(LengthPrefixedProtocol.read(input));
            }
        } catch (IOException error) {
            if (running && isActive(active)) {
                notifyError("连接已断开，等待 Mac 重新连接…");
            }
        } finally {
            if (isActive(active)) {
                closeClient();
                listener.onDisconnected();
            }
        }
    }

    private synchronized boolean isActive(Socket candidate) {
        return candidate == socket;
    }

    private synchronized void closeClient() {
        if (socket != null) {
            try {
                socket.close();
            } catch (IOException ignored) {
            }
        }
        socket = null;
        output = null;
    }

    private void notifyError(String message) {
        Listener activeListener = listener;
        if (activeListener != null) {
            activeListener.onError(message);
        }
    }
}

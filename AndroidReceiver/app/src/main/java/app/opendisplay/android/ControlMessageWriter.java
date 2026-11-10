package app.opendisplay.android;

import java.io.IOException;
import java.io.OutputStream;
import java.util.Objects;
import java.util.concurrent.Executor;
import java.util.concurrent.RejectedExecutionException;
import java.util.function.Consumer;

import app.opendisplay.android.protocol.LengthPrefixedProtocol;

public final class ControlMessageWriter {
    public static final int MAX_CONTROL_BYTES = WifiTcpReceiverTransport.MAX_CONTROL_BYTES;
    private final Executor executor;
    private final Consumer<IOException> errorHandler;

    public ControlMessageWriter(Executor executor) {
        this(executor, null);
    }

    public ControlMessageWriter(Executor executor, Consumer<IOException> errorHandler) {
        this.executor = Objects.requireNonNull(executor);
        this.errorHandler = errorHandler;
    }

    public boolean send(OutputStream output, String json) {
        if (output == null || json == null) {
            return false;
        }
        byte[] payload = LengthPrefixedProtocol.jsonBytes(json);
        if (payload.length == 0 || payload.length > MAX_CONTROL_BYTES) {
            if (errorHandler != null) {
                errorHandler.accept(new IOException(
                        "control message length out of bounds: " + payload.length));
            }
            return false;
        }
        try {
            executor.execute(() -> {
                try {
                    LengthPrefixedProtocol.write(output, payload);
                } catch (IOException error) {
                    if (errorHandler != null) {
                        errorHandler.accept(error);
                    }
                }
            });
            return true;
        } catch (RejectedExecutionException error) {
            if (errorHandler != null) {
                errorHandler.accept(new IOException(
                        "control message writer rejected task", error));
            }
            return false;
        }
    }
}

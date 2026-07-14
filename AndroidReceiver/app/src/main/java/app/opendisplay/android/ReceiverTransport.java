package app.opendisplay.android;

public interface ReceiverTransport {
    interface Listener {
        void onListening(int port);
        void onConnected(long generation, String peer);
        void onPayload(long generation, byte[] payload);
        default void onFrameLengthRejected(long generation, String reason,
                                           int frameBytes, int maximumBytes) {}
        default void onTransportDrop(long generation, String reason) {}
        void onDisconnected(long generation);
        void onError(long generation, String message);
    }

    String name();
    void start(Listener listener);
    default void setMaxFrameBytes(long generation, int maximumBytes) {}
    void send(long generation, byte[] payload);
    void stop();
    default void stop(byte[] finalPayload) {
        stop();
    }
}

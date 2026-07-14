package app.opendisplay.android;

public interface ReceiverTransport {
    interface Listener {
        void onListening(int port);
        void onConnected(long generation, String peer);
        void onPayload(long generation, byte[] payload);
        void onDisconnected(long generation);
        void onError(long generation, String message);
    }

    String name();
    void start(Listener listener);
    void send(long generation, byte[] payload);
    void stop();
    default void stop(byte[] finalPayload) {
        stop();
    }
}

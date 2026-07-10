package app.opendisplay.android;

public interface ReceiverTransport {
    interface Listener {
        void onListening(int port);
        void onConnected(String peer);
        void onPayload(byte[] payload);
        void onDisconnected();
        void onError(String message);
    }

    String name();
    void start(Listener listener);
    void send(byte[] payload);
    void stop();
}

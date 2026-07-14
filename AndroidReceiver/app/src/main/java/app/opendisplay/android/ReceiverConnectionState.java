package app.opendisplay.android;

/**
 * Observable application-layer progress for the current transport generation.
 * Session/config identity and acknowledgement semantics are intentionally deferred
 * to the negotiated protocol work; this state model must not imply those exist.
 */
public enum ReceiverConnectionState {
    DISCONNECTED,
    SOCKET_CONNECTED,
    HELLO_SENT,
    HELLO_ACCEPTED,
    STREAM_CONFIG_RECEIVED,
    STREAM_CONFIG_ACCEPTED,
    DECODER_CONFIGURING,
    DECODER_READY,
    WAITING_FIRST_FRAME,
    STREAMING,
    RECOVERING,
    FAILED
}

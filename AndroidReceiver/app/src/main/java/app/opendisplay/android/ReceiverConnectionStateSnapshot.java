package app.opendisplay.android;

public final class ReceiverConnectionStateSnapshot {
    public final ReceiverConnectionState state;
    public final String reason;
    public final long enteredAtMs;
    public final long generation;
    public final long sessionEpoch;
    public final long configVersion;

    ReceiverConnectionStateSnapshot(ReceiverConnectionState state, String reason,
                                    long enteredAtMs, long generation) {
        this(state, reason, enteredAtMs, generation, 0, 0);
    }

    ReceiverConnectionStateSnapshot(ReceiverConnectionState state, String reason,
                                    long enteredAtMs, long generation,
                                    long sessionEpoch, long configVersion) {
        this.state = state;
        this.reason = reason == null ? "" : reason;
        this.enteredAtMs = enteredAtMs;
        this.generation = generation;
        this.sessionEpoch = sessionEpoch;
        this.configVersion = configVersion;
    }
}

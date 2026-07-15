package app.opendisplay.android;

/** Tracks whether predictive frames are unsafe until a fresh keyframe arrives. */
final class ReferenceChainRecovery {
    private boolean awaitingKeyframe;
    private long startedAtMs;
    private long durationCheckpointMs;
    private long lastCompletedDurationMs;

    /** Returns true only for the transition into recovery. */
    boolean breakChain(long nowMs) {
        if (awaitingKeyframe) {
            return false;
        }
        awaitingKeyframe = true;
        startedAtMs = Math.max(0, nowMs);
        durationCheckpointMs = startedAtMs;
        return true;
    }

    /** Returns true when this frame must be rejected while recovery is active. */
    boolean shouldReject(boolean keyframe, long nowMs) {
        if (!awaitingKeyframe) {
            return false;
        }
        if (keyframe) {
            awaitingKeyframe = false;
            lastCompletedDurationMs = Math.max(0, nowMs - durationCheckpointMs);
            startedAtMs = 0;
            durationCheckpointMs = 0;
            return false;
        }
        return true;
    }

    boolean isAwaitingKeyframe() {
        return awaitingKeyframe;
    }

    long currentDurationMs(long nowMs) {
        return awaitingKeyframe ? Math.max(0, nowMs - startedAtMs) : 0;
    }

    long lastCompletedDurationMs() {
        return lastCompletedDurationMs;
    }

    /** Returns recovery time accrued since the previous sample. */
    long consumeDurationMs(long nowMs) {
        if (!awaitingKeyframe) {
            return 0;
        }
        long duration = Math.max(0, nowMs - durationCheckpointMs);
        durationCheckpointMs = Math.max(durationCheckpointMs, nowMs);
        return duration;
    }

    void reset() {
        awaitingKeyframe = false;
        startedAtMs = 0;
        durationCheckpointMs = 0;
        lastCompletedDurationMs = 0;
    }
}

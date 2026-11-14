package app.opendisplay.android;

/** Queue sizing for short transport and MediaCodec scheduling bursts. */
final class FrameQueuePolicy {
    // Four frames per FIFO (66 ms at 60 fps, 33 ms at 120 fps) absorb short
    // scheduling bursts while preventing deep 200+ ms latency accumulation.
    static final int MAX_PENDING_FRAMES = 4;
    // One receive-to-codec budget (75 ms) shared across both FIFOs; no clock sync needed.
    static final long MAX_QUEUE_AGE_NANOS = 75_000_000L;
    static boolean expired(long receivedNanos, long nowNanos) {
        return nowNanos - receivedNanos >= MAX_QUEUE_AGE_NANOS;
    }

    private FrameQueuePolicy() {
    }
}

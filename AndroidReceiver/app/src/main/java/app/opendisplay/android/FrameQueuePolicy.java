package app.opendisplay.android;

/** Queue sizing for short transport and MediaCodec scheduling bursts. */
final class FrameQueuePolicy {
    // Twelve frames absorb up to 200 ms at 60 fps (100 ms at 120 fps). The
    // queues remain empty in steady state; this is a burst ceiling, not fixed
    // latency. Real-device testing showed occasional scheduler stalls longer
    // than the previous six-frame (100 ms) ceiling.
    static final int MAX_PENDING_FRAMES = 12;

    private FrameQueuePolicy() {
    }
}

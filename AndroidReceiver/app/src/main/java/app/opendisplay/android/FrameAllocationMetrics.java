package app.opendisplay.android;

import android.os.Debug;

import java.util.Map;

/** Debug counters for transport allocation and zero-copy frame handoff. */
public final class FrameAllocationMetrics {
    public static final class Snapshot {
        public final long allocatedFrameBytes;
        public final long bufferReuseCount;
        public final long bufferPoolMiss;
        public final long gcCount;
        public final long gcTimeMs;

        Snapshot(long allocatedFrameBytes, long bufferReuseCount,
                 long bufferPoolMiss, long gcCount, long gcTimeMs) {
            this.allocatedFrameBytes = allocatedFrameBytes;
            this.bufferReuseCount = bufferReuseCount;
            this.bufferPoolMiss = bufferPoolMiss;
            this.gcCount = gcCount;
            this.gcTimeMs = gcTimeMs;
        }
    }

    private long allocatedFrameBytes;
    private long bufferReuseCount;
    private long bufferPoolMiss;
    private long lastGcCount;
    private long lastGcTimeMs;

    public FrameAllocationMetrics() {
        long[] baseline = runtimeGcMetrics();
        lastGcCount = baseline[0];
        lastGcTimeMs = baseline[1];
    }

    public synchronized void recordTransportFrame(int allocatedBytes, boolean zeroCopyView) {
        allocatedFrameBytes += Math.max(0, allocatedBytes);
        bufferPoolMiss++;
        if (zeroCopyView) {
            bufferReuseCount++;
        }
    }

    public synchronized Snapshot snapshotAndResetWindow() {
        long[] gc = runtimeGcMetrics();
        long gcCountDelta = counterDelta(lastGcCount, gc[0]);
        long gcTimeDelta = counterDelta(lastGcTimeMs, gc[1]);
        lastGcCount = gc[0];
        lastGcTimeMs = gc[1];
        Snapshot snapshot = new Snapshot(
                allocatedFrameBytes, bufferReuseCount, bufferPoolMiss,
                gcCountDelta, gcTimeDelta);
        allocatedFrameBytes = 0;
        bufferReuseCount = 0;
        bufferPoolMiss = 0;
        return snapshot;
    }

    static long counterDelta(long previous, long current) {
        if (previous < 0 || current < 0 || current < previous) {
            return 0;
        }
        return current - previous;
    }

    private static long[] runtimeGcMetrics() {
        try {
            Map<String, String> stats = Debug.getRuntimeStats();
            return new long[] {
                    parse(stats.get("art.gc.gc-count")),
                    parse(stats.get("art.gc.gc-time"))
            };
        } catch (Throwable ignored) {
            return new long[] {0, 0};
        }
    }

    private static long parse(String value) {
        if (value == null) return 0;
        try {
            return Math.max(0, Long.parseLong(value));
        } catch (NumberFormatException ignored) {
            return 0;
        }
    }
}

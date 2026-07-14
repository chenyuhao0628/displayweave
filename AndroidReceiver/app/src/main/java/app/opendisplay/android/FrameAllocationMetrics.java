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

    public synchronized void recordTransportFrame(int allocatedBytes, boolean zeroCopyView) {
        allocatedFrameBytes += Math.max(0, allocatedBytes);
        bufferPoolMiss++;
        if (zeroCopyView) {
            bufferReuseCount++;
        }
    }

    public synchronized Snapshot snapshotAndResetWindow() {
        long[] gc = runtimeGcMetrics();
        Snapshot snapshot = new Snapshot(
                allocatedFrameBytes, bufferReuseCount, bufferPoolMiss,
                gc[0], gc[1]);
        allocatedFrameBytes = 0;
        bufferReuseCount = 0;
        bufferPoolMiss = 0;
        return snapshot;
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

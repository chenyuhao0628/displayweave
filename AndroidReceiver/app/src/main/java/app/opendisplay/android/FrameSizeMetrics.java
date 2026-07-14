package app.opendisplay.android;

import app.opendisplay.android.protocol.LengthPrefixedProtocol;

public final class FrameSizeMetrics {
    public static final class Snapshot {
        public final long currentFrameBytes;
        public final long maxFrameBytesObserved;
        public final long currentKeyframeBytes;
        public final long maxKeyframeBytesObserved;
        public final long oversizeFrameCount;
        public final long invalidFrameLengthCount;

        Snapshot(long currentFrameBytes, long maxFrameBytesObserved,
                 long currentKeyframeBytes, long maxKeyframeBytesObserved,
                 long oversizeFrameCount, long invalidFrameLengthCount) {
            this.currentFrameBytes = currentFrameBytes;
            this.maxFrameBytesObserved = maxFrameBytesObserved;
            this.currentKeyframeBytes = currentKeyframeBytes;
            this.maxKeyframeBytesObserved = maxKeyframeBytesObserved;
            this.oversizeFrameCount = oversizeFrameCount;
            this.invalidFrameLengthCount = invalidFrameLengthCount;
        }
    }

    private long currentFrameBytes;
    private long maxFrameBytesObserved;
    private long currentKeyframeBytes;
    private long maxKeyframeBytesObserved;
    private long oversizeFrameCount;
    private long invalidFrameLengthCount;

    public synchronized void recordFrame(long frameBytes, boolean keyframe) {
        currentFrameBytes = Math.max(0, frameBytes);
        maxFrameBytesObserved = Math.max(maxFrameBytesObserved, currentFrameBytes);
        if (keyframe) {
            currentKeyframeBytes = currentFrameBytes;
            maxKeyframeBytesObserved = Math.max(
                    maxKeyframeBytesObserved, currentKeyframeBytes);
        }
    }

    public synchronized void recordRejected(
            LengthPrefixedProtocol.FrameLengthFailure failure) {
        invalidFrameLengthCount++;
        if (failure == LengthPrefixedProtocol.FrameLengthFailure.OVERSIZE
                || failure == LengthPrefixedProtocol.FrameLengthFailure.ABSOLUTE_LIMIT) {
            oversizeFrameCount++;
        }
    }

    public synchronized void resetCurrent() {
        currentFrameBytes = 0;
        currentKeyframeBytes = 0;
    }

    public synchronized Snapshot snapshot() {
        return new Snapshot(
                currentFrameBytes,
                maxFrameBytesObserved,
                currentKeyframeBytes,
                maxKeyframeBytesObserved,
                oversizeFrameCount,
                invalidFrameLengthCount);
    }
}

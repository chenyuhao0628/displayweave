package app.opendisplay.android;

import java.util.concurrent.atomic.AtomicBoolean;
import java.util.function.Consumer;

/** Executor shutdown/rejection can release a queued frame without running its event. */
final class OwnedFrameTask implements Runnable, AutoCloseable {
    private final FrameBufferPool.Lease lease;
    private final Consumer<FrameBufferPool.Lease> consumer;
    private final AtomicBoolean claimed = new AtomicBoolean();
    OwnedFrameTask(FrameBufferPool.Lease borrowed, Consumer<FrameBufferPool.Lease> consumer) {
        this.lease = borrowed.retain(); this.consumer = consumer;
    }
    @Override public void run() {
        if (!claimed.compareAndSet(false, true)) return;
        try { consumer.accept(lease); } finally { lease.close(); }
    }
    @Override public void close() {
        if (claimed.compareAndSet(false, true)) lease.close();
    }
}

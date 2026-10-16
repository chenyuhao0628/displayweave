package app.opendisplay.android;

import java.io.IOException;
import java.util.ArrayDeque;
import java.util.Iterator;
import java.util.concurrent.atomic.AtomicBoolean;

/** Bounded transport storage. Each async owner holds a separately closeable lease. */
public final class FrameBufferPool implements AutoCloseable {
    private final int maximumBytes;
    private final int maximumBuffers;
    private final long waitMillis;
    private final ArrayDeque<byte[]> idle = new ArrayDeque<>();
    private int allocatedBytes;
    private int allocatedBuffers;
    private int inUse;
    private boolean closed;

    public FrameBufferPool() { this(32 * 1024 * 1024, 32, 250); }
    FrameBufferPool(int maximumBytes, int maximumBuffers, long waitMillis) {
        if (maximumBytes < 1024 || maximumBuffers < 1 || waitMillis < 0 || waitMillis > 1000) {
            throw new IllegalArgumentException("invalid pool bounds");
        }
        this.maximumBytes = maximumBytes;
        this.maximumBuffers = maximumBuffers;
        this.waitMillis = waitMillis;
    }

    private static final class Storage {
        final byte[] bytes;
        int references = 1; // guarded by pool
        Storage(byte[] bytes) { this.bytes = bytes; }
    }

    public static final class Lease implements AutoCloseable {
        private final FrameBufferPool pool;
        private final Storage storage;
        private final AtomicBoolean closed = new AtomicBoolean();
        public final int length;
        public final int allocatedBytes;
        public final boolean reused;
        private Lease(FrameBufferPool pool, Storage storage, int length, boolean reused) {
            this.pool = pool; this.storage = storage; this.length = length; this.reused = reused;
            this.allocatedBytes = reused ? 0 : storage.bytes.length;
        }
        public byte[] bytes() {
            if (closed.get()) throw new IllegalStateException("closed frame lease");
            return storage.bytes;
        }
        public Lease retain() {
            synchronized (pool) {
                if (closed.get()) throw new IllegalStateException("closed frame lease");
                if (storage.references <= 0) throw new IllegalStateException("returned frame storage");
                storage.references++;
                return new Lease(pool, storage, length, reused);
            }
        }
        @Override public void close() {
            if (closed.compareAndSet(false, true)) pool.release(storage);
        }
    }

    public synchronized Lease acquire(int length) throws IOException {
        if (length <= 0 || length > Math.min(maximumBytes, 16 * 1024 * 1024)) {
            throw new IOException("frame exceeds pool bound");
        }
        int capacity = 1024;
        while (capacity < length) capacity *= 2;
        if (capacity > maximumBytes) throw new IOException("frame bucket exceeds pool bound");
        long deadline = System.nanoTime() + waitMillis * 1_000_000;
        while (!closed) {
            for (Iterator<byte[]> iterator = idle.iterator(); iterator.hasNext();) {
                byte[] bytes = iterator.next();
                if (bytes.length == capacity) {
                    iterator.remove(); inUse++;
                    return new Lease(this, new Storage(bytes), length, true);
                }
            }
            while (!idle.isEmpty() && (allocatedBytes + capacity > maximumBytes
                    || allocatedBuffers >= maximumBuffers)) {
                allocatedBytes -= idle.removeFirst().length;
                allocatedBuffers--;
            }
            if (allocatedBytes + capacity <= maximumBytes && allocatedBuffers < maximumBuffers) {
                byte[] bytes = new byte[capacity];
                allocatedBytes += capacity; allocatedBuffers++; inUse++;
                return new Lease(this, new Storage(bytes), length, false);
            }
            long remaining = deadline - System.nanoTime();
            if (remaining <= 0) throw new IOException("frame pool saturated for bounded wait");
            try { wait(Math.max(1, remaining / 1_000_000)); }
            catch (InterruptedException error) {
                Thread.currentThread().interrupt();
                throw new IOException("frame pool wait interrupted", error);
            }
        }
        throw new IOException("frame pool closed");
    }

    private synchronized void release(Storage storage) {
        if (--storage.references != 0) return;
        inUse--;
        if (closed) { allocatedBytes -= storage.bytes.length; allocatedBuffers--; }
        else { idle.addLast(storage.bytes); }
        notifyAll();
    }
    synchronized int inUseBuffers() { return inUse; }
    synchronized int allocatedBytes() { return allocatedBytes; }
    @Override public synchronized void close() {
        closed = true;
        while (!idle.isEmpty()) { allocatedBytes -= idle.removeFirst().length; allocatedBuffers--; }
        notifyAll();
    }
}

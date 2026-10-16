package app.opendisplay.android;

import app.opendisplay.android.protocol.BinaryFrameHeaderV2;
import app.opendisplay.android.protocol.LengthPrefixedProtocol;
import java.io.ByteArrayInputStream;
import java.io.IOException;
import java.util.Arrays;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.atomic.AtomicReference;

final class FrameBufferPoolSelfTest {
    static void run() throws Exception {
        FrameBufferPool pool = new FrameBufferPool(4096, 2, 20);
        FrameBufferPool.Lease a = pool.acquire(100);
        byte[] original = a.bytes();
        a.bytes()[0] = 42;
        FrameBufferPool.Lease retained = a.retain();
        a.close(); a.close();
        expect(pool.inUseBuffers() == 1, "double close must not recycle retained storage");
        try (FrameBufferPool.Lease b = pool.acquire(120)) {
            expect(b.bytes() != original && retained.bytes()[0] == 42, "in-flight bytes never reused");
            try { pool.acquire(120); throw new AssertionError("unbounded pool"); }
            catch (IOException expected) { }
        }
        retained.close();
        try (FrameBufferPool.Lease reused = pool.acquire(100)) {
            expect(reused.reused && reused.allocatedBytes == 0, "idle bucket reused");
            try { a.retain(); throw new AssertionError("closed handle retained"); }
            catch (IllegalStateException expected) { }
        }
        byte[] video = BinaryFrameHeaderV2.encode(BinaryFrameHeaderV2.FLAG_H264,
                1, 1, 1, 1, 2, new byte[]{0, 0, 0, 1, 0x65, 1});
        VideoFramePacket packet;
        try (FrameBufferPool.Lease wire = pool.acquire(video.length)) {
            System.arraycopy(video, 0, wire.bytes(), 0, video.length);
            Arrays.fill(wire.bytes(), video.length, wire.bytes().length, (byte) 0x7f);
            packet = VideoFramePacket.parse(wire, 10, VideoStreamConfig.DEFAULT);
            expect(packet.payloadLength == 6, "bucket tail is not frame payload");
        }
        expect(pool.inUseBuffers() == 1 && packet.hasAnnexBPayload(), "packet owns lease after transport returns");
        VideoFramePacket decoderPending = packet.retained();
        packet.close();
        expect(decoderPending.hasAnnexBPayload(), "asynchronous decoder keeps bytes live");
        decoderPending.close();
        expect(pool.inUseBuffers() == 0, "decoder completion returns buffer");
        byte[] framed = LengthPrefixedProtocol.encode(video);
        try (FrameBufferPool.Lease read = LengthPrefixedProtocol.readPooled(
                new ByteArrayInputStream(framed), 1024, pool)) {
            expect(read.length == video.length, "wire length independent of bucket capacity");
        }
        try {
            LengthPrefixedProtocol.readPooled(new ByteArrayInputStream(
                    Arrays.copyOf(framed, framed.length - 2)), 1024, pool);
            throw new AssertionError("truncation accepted");
        } catch (IOException expected) { }
        expect(pool.inUseBuffers() == 0, "failed read returns lease");
        try {
            LengthPrefixedProtocol.readPooled(new ByteArrayInputStream(new byte[]{127, -1, -1, -1}), 1024, pool);
            throw new AssertionError("oversize allocation");
        } catch (LengthPrefixedProtocol.FrameLengthException expected) { }
        expect(pool.inUseBuffers() == 0 && pool.allocatedBytes() <= 4096, "length checked before allocation");
        FrameBufferPool.Lease shutdown = pool.acquire(120);
        pool.close(); shutdown.close();
        expect(pool.allocatedBytes() == 0, "shutdown discards idle and late returns");
        testConcurrentOwnership();
        testTaskOwnership();
        testLegacyAndAllocationWindow();
        testTransportOwnership();
        System.out.println("FrameBufferPoolSelfTest PASS");
    }

    private static void testTaskOwnership() throws Exception {
        FrameBufferPool pool = new FrameBufferPool(4096, 4, 0);
        java.util.concurrent.atomic.AtomicInteger calls = new java.util.concurrent.atomic.AtomicInteger();
        OwnedFrameTask cancelled;
        try (FrameBufferPool.Lease lease = pool.acquire(100)) {
            cancelled = new OwnedFrameTask(lease, ignored -> calls.incrementAndGet());
        }
        cancelled.close(); cancelled.close(); cancelled.run();
        expect(calls.get() == 0 && pool.inUseBuffers() == 0, "shutdown cancels ownership exactly once");
        OwnedFrameTask throwing;
        try (FrameBufferPool.Lease lease = pool.acquire(100)) {
            throwing = new OwnedFrameTask(lease, ignored -> { throw new IllegalArgumentException("fixture"); });
        }
        try { throwing.run(); throw new AssertionError("consumer did not run"); }
        catch (IllegalArgumentException expected) { }
        throwing.close();
        expect(pool.inUseBuffers() == 0, "consumer exception returns lease");
        java.util.concurrent.ExecutorService stopped = java.util.concurrent.Executors.newSingleThreadExecutor();
        stopped.shutdownNow();
        try (FrameBufferPool.Lease lease = pool.acquire(100)) {
            OwnedFrameTask rejected = new OwnedFrameTask(lease, ignored -> calls.incrementAndGet());
            try { stopped.execute(rejected); throw new AssertionError("task accepted after stop"); }
            catch (java.util.concurrent.RejectedExecutionException expected) { rejected.close(); }
        }
        expect(pool.inUseBuffers() == 0, "executor rejection returns lease");
        pool.close();
    }

    private static void testLegacyAndAllocationWindow() throws Exception {
        FrameBufferPool pool = new FrameBufferPool(4096, 2, 0);
        byte[] legacy = "{\"seq\":1}".getBytes(java.nio.charset.StandardCharsets.UTF_8);
        byte[] frame = Arrays.copyOf(legacy, legacy.length + 6);
        System.arraycopy(new byte[]{0, 0, 0, 1, 0x65, 1}, 0, frame, legacy.length, 6);
        try (FrameBufferPool.Lease lease = pool.acquire(frame.length)) {
            Arrays.fill(lease.bytes(), (byte) 0x7f);
            System.arraycopy(frame, 0, lease.bytes(), 0, frame.length);
            try (VideoFramePacket packet = VideoFramePacket.parse(lease, 10, VideoStreamConfig.DEFAULT)) {
                expect(packet.payloadLength == 6 && packet.keyframe, "legacy parser excludes bucket tail");
            }
        }
        pool.close();
        FrameBufferPool measured = new FrameBufferPool(4096, 2, 0);
        FrameAllocationMetrics metrics = new FrameAllocationMetrics();
        for (int n = 0; n < 1000; n++) {
            try (FrameBufferPool.Lease lease = measured.acquire(1000)) {
                metrics.recordTransportFrame(lease.allocatedBytes, lease.reused);
            }
        }
        FrameAllocationMetrics.Snapshot result = metrics.snapshotAndResetWindow();
        expect(result.allocatedFrameBytes == 1024 && result.bufferReuseCount == 999
                && result.bufferPoolMiss == 1, "1000 synthetic frames allocate one bucket");
        measured.close();
    }

    private static void testTransportOwnership() throws Exception {
        FrameBufferPool pool = new FrameBufferPool(4096, 2, 25);
        WifiTcpReceiverTransport transport = WifiTcpReceiverTransport.legacy(0,
                WifiTcpReceiverTransport.boundedExecutor(1, 4), pool);
        java.util.concurrent.LinkedBlockingQueue<FrameBufferPool.Lease> frames =
                new java.util.concurrent.LinkedBlockingQueue<>();
        CountDownLatch listening = new CountDownLatch(1);
        CountDownLatch disconnected = new CountDownLatch(1);
        java.util.concurrent.atomic.AtomicInteger port = new java.util.concurrent.atomic.AtomicInteger();
        transport.start(new ReceiverTransport.Listener() {
            public void onListening(int value) { port.set(value); listening.countDown(); }
            public void onConnected(long generation, String peer) { }
            public void onPayload(long generation, byte[] payload) { throw new AssertionError("copy path used"); }
            public void onFrame(long generation, FrameBufferPool.Lease borrowed) { frames.add(borrowed.retain()); }
            public void onDisconnected(long generation) { disconnected.countDown(); }
            public void onError(long generation, String message) { }
        });
        try {
            expect(listening.await(2, java.util.concurrent.TimeUnit.SECONDS), "transport listening");
            try (java.net.Socket first = new java.net.Socket("127.0.0.1", port.get())) {
                LengthPrefixedProtocol.write(first.getOutputStream(), new byte[]{42, 43});
                FrameBufferPool.Lease held = frames.poll(2, java.util.concurrent.TimeUnit.SECONDS);
                expect(held != null, "transport delivered borrowed frame");
                try (FrameBufferPool.Lease retained = held;
                     java.net.Socket second = new java.net.Socket("127.0.0.1", port.get())) {
                    LengthPrefixedProtocol.write(second.getOutputStream(), new byte[]{12, 13, 14});
                    FrameBufferPool.Lease next = frames.poll(2, java.util.concurrent.TimeUnit.SECONDS);
                    expect(next != null, "replacement transport delivered frame");
                    try (FrameBufferPool.Lease replacement = next) {
                        expect(held.bytes() != next.bytes() && held.bytes()[0] == 42,
                                "replacement cannot reuse retained old-generation frame");
                        LengthPrefixedProtocol.write(second.getOutputStream(), new byte[]{99});
                        expect(disconnected.await(2, java.util.concurrent.TimeUnit.SECONDS),
                                "exhaustion disconnects within bounded wait");
                        transport.stop();
                        expect(held.bytes()[0] == 42 && next.bytes()[0] == 12,
                                "shutdown does not invalidate consumer-owned bytes");
                    }
                }
            }
        } finally {
            transport.stop();
            for (FrameBufferPool.Lease lease : frames) lease.close();
        }
        expect(pool.inUseBuffers() == 0 && pool.allocatedBytes() == 0,
                "reconnect, pool saturation and stop release all storage");
    }

    private static void testConcurrentOwnership() throws Exception {
        FrameBufferPool pool = new FrameBufferPool(8192, 4, 250);
        CountDownLatch start = new CountDownLatch(1);
        AtomicReference<Throwable> failure = new AtomicReference<>();
        Thread[] threads = new Thread[4];
        for (int i = 0; i < threads.length; i++) {
            final byte marker = (byte) (i + 1);
            threads[i] = new Thread(() -> {
                try {
                    start.await();
                    for (int n = 0; n < 100; n++) {
                        try (FrameBufferPool.Lease lease = pool.acquire(1000)) {
                            Arrays.fill(lease.bytes(), marker);
                            Thread.yield();
                            expect(lease.bytes()[999] == marker, "concurrent alias");
                        }
                    }
                } catch (Throwable error) { failure.compareAndSet(null, error); }
            });
            threads[i].start();
        }
        start.countDown();
        for (Thread thread : threads) thread.join(5000);
        for (Thread thread : threads) expect(!thread.isAlive(), "unbounded wait");
        if (failure.get() != null) throw new AssertionError(failure.get());
        expect(pool.inUseBuffers() == 0 && pool.allocatedBytes() <= 8192, "bounded concurrent completion");
        pool.close();
    }
    private static void expect(boolean value, String message) {
        if (!value) throw new AssertionError(message);
    }
}

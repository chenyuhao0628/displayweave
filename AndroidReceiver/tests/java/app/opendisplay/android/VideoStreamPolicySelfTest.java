package app.opendisplay.android;

import java.io.BufferedInputStream;
import java.io.BufferedOutputStream;
import java.net.Socket;
import java.nio.charset.StandardCharsets;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.concurrent.atomic.AtomicReference;

import app.opendisplay.android.protocol.LengthPrefixedProtocol;

public final class VideoStreamPolicySelfTest {
    public static void main(String[] args) {
        testStreamConfigDefaults();
        testCodecMapping();
        testRefreshModeSelection();
        testFrameClassifier();
        testFrameTelemetry();
        testStreamMetricsLatencyFields();
        testMetricDistribution();
        testClockOffsetEstimator();
        testStatsPublicationWindowBoundary();
        testMacPingMetricsParsing();
        testCodecFallbackStatus();
        testWifiTransportCarriesFramedPayloads();
        testWifiTransportIgnoresSendAfterStop();
        System.out.println("VideoStreamPolicySelfTest PASS");
    }

    private static void testStreamConfigDefaults() {
        VideoStreamConfig config = VideoStreamConfig.from("hevc", 144, 2560, 1600, 60_000_000);
        assertEquals("hevc", config.codec);
        assertEquals("video/hevc", config.mimeType);
        assertEquals(120, config.fps);
        assertEquals(19, config.keyframeNalType());
    }

    private static void testCodecMapping() {
        VideoStreamConfig hevc = VideoStreamConfig.from("hevc", 90, 1920, 1080, 30_000_000);
        assertEquals("video/hevc", hevc.mimeType);
        assertEquals(32, hevc.vpsNalType());
        assertEquals(33, hevc.spsNalType());
        assertEquals(34, hevc.ppsNalType());
        assertEquals(19, hevc.keyframeNalType());

        VideoStreamConfig h264 = VideoStreamConfig.from("h264", 60, 1920, 1080, 18_000_000);
        assertEquals("video/avc", h264.mimeType);
        assertEquals(-1, h264.vpsNalType());
        assertEquals(7, h264.spsNalType());
        assertEquals(8, h264.ppsNalType());
        assertEquals(5, h264.keyframeNalType());

        VideoStreamConfig unknown = VideoStreamConfig.from("vp9", 55, 1280, 720, 0);
        assertEquals("h264", unknown.codec);
        assertEquals(60, unknown.fps);
    }

    private static void testRefreshModeSelection() {
        float[] modes = new float[] {60f, 90f, 120f};
        assertEquals(120f, RefreshRateController.chooseRefreshRate(118, modes, 60f));
        assertEquals(90f, RefreshRateController.chooseRefreshRate(90, modes, 60f));
        assertEquals(60f, RefreshRateController.chooseRefreshRate(75, modes, 60f));
        assertEquals(60f, RefreshRateController.chooseRefreshRate(120, new float[] {60f}, 60f));
    }

    private static void testFrameClassifier() {
        VideoStreamConfig h264 = VideoStreamConfig.from("h264", 60, 1920, 1080, 0);
        assertTrue(VideoFrameClassifier.isImportant(
                annexB((byte) 0x67, (byte) 0x68, (byte) 0x65), h264));
        assertFalse(VideoFrameClassifier.isImportant(annexB((byte) 0x41), h264));

        VideoStreamConfig hevc = VideoStreamConfig.from("hevc", 120, 2560, 1600, 0);
        assertTrue(VideoFrameClassifier.isImportant(
                hevcAnnexB(32, 33, 19), hevc));
        assertFalse(VideoFrameClassifier.isImportant(hevcAnnexB(1), hevc));
    }

    private static void testFrameTelemetry() {
        byte[] prefix = "{\"cap\":1000,\"snd\":1015}".getBytes(java.nio.charset.StandardCharsets.UTF_8);
        byte[] payload = concat(prefix, annexB((byte) 0x65));
        VideoFrameTelemetry telemetry = VideoFrameTelemetry.fromWirePayload(payload, 200);
        assertEquals(1000L, telemetry.captureMacMs);
        assertEquals(1015L, telemetry.sendMacMs);
        assertEquals(200L, telemetry.receivedAndroidMs);

        VideoFrameTelemetry empty = VideoFrameTelemetry.fromWirePayload(annexB((byte) 0x41), 300);
        assertEquals(-1L, empty.captureMacMs);
        assertEquals(-1L, empty.sendMacMs);
        assertEquals(300L, empty.receivedAndroidMs);
    }

    private static void testStreamMetricsLatencyFields() {
        StreamMetrics metrics = new StreamMetrics(
                119, 118, 117, 12.5, 4.0, 120,
                120, "hevc", 50_000_000, 2, 1, 120f,
                8, 22, 6,
                120, 119, 118, 425_000, 4, 3, 2, "wifi");
        assertEquals(117, metrics.decodedFps);
        assertEquals(8, metrics.latestFrameAgeMs);
        assertEquals(22, metrics.endToEndLatencyMs);
        assertEquals(6, metrics.decodeLatencyMs);
        assertEquals(120, metrics.actualVirtualDisplayRefreshRate);
        assertEquals(119, metrics.encodedFps);
        assertEquals(118, metrics.sentFps);
        assertEquals(425_000, metrics.averageFrameSize);
        assertEquals(4, metrics.encodeLatencyMs);
        assertEquals(3, metrics.queueDepthMac);
        assertEquals(2, metrics.droppedFramesMac);
        assertEquals("wifi", metrics.transport);
    }

    private static void testCodecFallbackStatus() {
        assertEquals("HEVC 不可用，已请求回退 H.264",
                CodecFallbackStatus.messageForCodecFailure("hevc"));
        assertEquals(null, CodecFallbackStatus.messageForCodecFailure("h264"));
    }

    private static void testMetricDistribution() {
        MetricDistribution distribution = new MetricDistribution(4);
        assertEquals(MetricDistribution.MISSING_MS, distribution.latest());
        assertEquals(MetricDistribution.MISSING_MS, distribution.p50());
        assertEquals(MetricDistribution.MISSING_MS, distribution.p95());
        assertEquals(MetricDistribution.MISSING_MS, distribution.p99());

        distribution.add(40);
        distribution.add(10);
        distribution.add(30);
        distribution.add(20);
        assertEquals(20L, distribution.latest());
        assertEquals(20L, distribution.p50());
        assertEquals(40L, distribution.p95());
        assertEquals(40L, distribution.p99());

        distribution.add(5);
        assertEquals(4, distribution.size());
        assertEquals(5L, distribution.latest());
        assertEquals(10L, distribution.p50());
        assertEquals(30L, distribution.p95());
    }

    private static void testClockOffsetEstimator() {
        ClockOffsetEstimator estimator = new ClockOffsetEstimator(4);
        assertEquals(ClockOffsetEstimator.State.ESTIMATING, estimator.state());
        assertFalse(estimator.addSample(0, 300, 300, 300));
        assertFalse(estimator.addSample(300, 0, 0, 0));
        assertEquals(0, estimator.sampleCount());

        assertTrue(estimator.addSample(1000, 1012, 1014, 1006)); // offset 10, RTT 4
        assertTrue(estimator.addSample(2000, 2014, 2016, 2008)); // offset 11, RTT 6
        assertEquals(ClockOffsetEstimator.State.ESTIMATING, estimator.state());
        assertTrue(estimator.addSample(3000, 3014, 3016, 3010)); // offset 10, RTT 8
        assertEquals(ClockOffsetEstimator.State.STABLE, estimator.state());
        assertEquals(11L, estimator.offsetMs());
        assertEquals(1L, estimator.confidenceMs());

        assertTrue(estimator.addSample(4000, 4102, 4104, 4200)); // offset 1, RTT 198
        assertTrue(estimator.addSample(5000, 5022, 5024, 5020)); // offset 11, RTT 18; evicts first
        assertEquals(4, estimator.sampleCount());
        assertEquals(11L, estimator.offsetMs());
        assertEquals(1L, estimator.confidenceMs());
    }

    private static void testStatsPublicationWindowBoundary() {
        assertFalse(OpenDisplayServer.shouldPublishStats(999));
        assertTrue(OpenDisplayServer.shouldPublishStats(1000));
    }

    private static void testMacPingMetricsParsing() {
        OpenDisplayServer.MacPingMetrics metrics = OpenDisplayServer.MacPingMetrics.parse(
                "{\"type\":\"ping\",\"inp50\":3.5,\"inputP95Ms\":8.25,\"requestedFps\":120}",
                0, 0, 60);
        assertEquals(3.5, metrics.inputP50Ms);
        assertEquals(8.25, metrics.inputP95Ms);
        assertEquals(120, metrics.requestedFps);
    }

    private static void testWifiTransportCarriesFramedPayloads() {
        ReceiverTransport transport = new WifiTcpReceiverTransport(0);
        AtomicInteger listeningPort = new AtomicInteger();
        AtomicReference<byte[]> received = new AtomicReference<>();
        CountDownLatch listening = new CountDownLatch(1);
        CountDownLatch connected = new CountDownLatch(1);
        CountDownLatch payloadReceived = new CountDownLatch(1);

        transport.start(new ReceiverTransport.Listener() {
            @Override public void onListening(int port) {
                listeningPort.set(port);
                listening.countDown();
            }
            @Override public void onConnected(String peer) { connected.countDown(); }
            @Override public void onPayload(byte[] payload) {
                received.set(payload);
                payloadReceived.countDown();
            }
            @Override public void onDisconnected() { }
            @Override public void onError(String message) {
                throw new AssertionError(message);
            }
        });

        try {
            assertTrue(listening.await(2, TimeUnit.SECONDS));
            assertEquals("wifi", transport.name());
            try (Socket client = new Socket("127.0.0.1", listeningPort.get())) {
                client.setSoTimeout(2000);
                assertTrue(connected.await(2, TimeUnit.SECONDS));
                BufferedOutputStream output = new BufferedOutputStream(client.getOutputStream());
                LengthPrefixedProtocol.write(output, "from-mac".getBytes(StandardCharsets.UTF_8));
                output.flush();
                assertTrue(payloadReceived.await(2, TimeUnit.SECONDS));
                assertEquals("from-mac", new String(received.get(), StandardCharsets.UTF_8));

                transport.send("from-android".getBytes(StandardCharsets.UTF_8));
                byte[] reply = LengthPrefixedProtocol.read(
                        new BufferedInputStream(client.getInputStream()));
                assertEquals("from-android", new String(reply, StandardCharsets.UTF_8));
            }
        } catch (Exception error) {
            throw new AssertionError("WiFi transport loopback failed", error);
        } finally {
            transport.stop();
        }
    }

    private static void testWifiTransportIgnoresSendAfterStop() {
        ReceiverTransport transport = new WifiTcpReceiverTransport(0);
        transport.stop();
        try {
            transport.send("late-ping".getBytes(StandardCharsets.UTF_8));
        } catch (RuntimeException error) {
            throw new AssertionError("send after stop must be a no-op", error);
        }
    }

    private static byte[] annexB(byte... nalHeaders) {
        byte[] out = new byte[nalHeaders.length * 5];
        int offset = 0;
        for (byte header : nalHeaders) {
            out[offset++] = 0;
            out[offset++] = 0;
            out[offset++] = 0;
            out[offset++] = 1;
            out[offset++] = header;
        }
        return out;
    }

    private static byte hevcNal(int type) {
        return (byte) ((type & 0x3F) << 1);
    }

    private static byte[] hevcAnnexB(int... nalTypes) {
        byte[] out = new byte[nalTypes.length * 6];
        int offset = 0;
        for (int type : nalTypes) {
            out[offset++] = 0;
            out[offset++] = 0;
            out[offset++] = 0;
            out[offset++] = 1;
            out[offset++] = hevcNal(type);
            out[offset++] = 1;
        }
        return out;
    }

    private static byte[] concat(byte[] first, byte[] second) {
        byte[] out = new byte[first.length + second.length];
        System.arraycopy(first, 0, out, 0, first.length);
        System.arraycopy(second, 0, out, first.length, second.length);
        return out;
    }

    private static void assertEquals(Object expected, Object actual) {
        if (expected == null ? actual != null : !expected.equals(actual)) {
            throw new AssertionError("expected " + expected + " but got " + actual);
        }
    }

    private static void assertEquals(float expected, float actual) {
        if (Math.abs(expected - actual) > 0.001f) {
            throw new AssertionError("expected " + expected + " but got " + actual);
        }
    }

    private static void assertTrue(boolean value) {
        if (!value) throw new AssertionError("expected true");
    }

    private static void assertFalse(boolean value) {
        if (value) throw new AssertionError("expected false");
    }
}

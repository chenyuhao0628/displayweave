package app.opendisplay.android;

import java.io.BufferedInputStream;
import java.io.BufferedOutputStream;
import java.net.Socket;
import java.nio.charset.StandardCharsets;
import java.util.List;
import java.util.concurrent.CopyOnWriteArrayList;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.concurrent.atomic.AtomicLong;
import java.util.concurrent.atomic.AtomicReference;

import app.opendisplay.android.protocol.LengthPrefixedProtocol;
import app.opendisplay.android.protocol.BinaryFrameHeaderV2;

public final class VideoStreamPolicySelfTest {
    public static void main(String[] args) throws Exception {
        testStreamConfigDefaults();
        testCodecMapping();
        testProtocolV2FrameIdentity();
        testProtocolV2SessionFiltering();
        testRefreshModeSelection();
        testFrameClassifier();
        testVideoFramePacketUsesZeroCopyBinaryPayloadView();
        testFrameSizeMetrics();
        testFrameAllocationMetrics();
        testFrameTelemetry();
        testStreamMetricsLatencyFields();
        testMetricDistribution();
        testClockOffsetEstimator();
        testStatsPublicationWindowBoundary();
        testMacPingMetricsParsing();
        testCodecFallbackStatus();
        testDecoderStallRecoveryPolicy();
        testDecoderReconfigurationPolicy();
        testDecoderLowLatencyMode();
        testDecoderSelectionAndFallbackOrder();
        testDecoderRuntimeFailureMetrics();
        testWifiLowLatencyLifecycle();
        testSurfaceFrameRateLifecycle();
        testAndroidDropReasonClassification();
        testAcceptedSocketOptions();
        testWifiTransportCarriesFramedPayloads();
        testWifiTransportKeepsLegacyFrameLimit();
        testWifiTransportAcceptsV2FrameSize();
        testWifiTransportRejectsOversizeWithReason();
        testWifiTransportReplacesBlockedConnection();
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

    private static void testProtocolV2FrameIdentity() {
        byte[] payload = concat(
                "{\"cap\":1,\"snd\":2,\"se\":8,\"cv\":12,\"fs\":41}"
                        .getBytes(StandardCharsets.UTF_8),
                new byte[] {0, 0, 0, 1, 0x65, 1});
        VideoFrameTelemetry telemetry = VideoFrameTelemetry.fromWirePayload(payload, 3);
        assertEquals(8L, telemetry.sessionEpoch);
        assertEquals(12L, telemetry.configVersion);
        assertEquals(41L, telemetry.frameSequence);
    }

    private static void testFrameSizeMetrics() {
        FrameSizeMetrics metrics = new FrameSizeMetrics();
        metrics.recordFrame(1_024, false);
        metrics.recordFrame(4_096, true);
        metrics.recordFrame(2_048, false);
        metrics.recordRejected(LengthPrefixedProtocol.FrameLengthFailure.OVERSIZE);
        metrics.recordRejected(LengthPrefixedProtocol.FrameLengthFailure.INVALID_LENGTH);
        FrameSizeMetrics.Snapshot snapshot = metrics.snapshot();
        assertEquals(2_048L, snapshot.currentFrameBytes);
        assertEquals(4_096L, snapshot.maxFrameBytesObserved);
        assertEquals(4_096L, snapshot.currentKeyframeBytes);
        assertEquals(4_096L, snapshot.maxKeyframeBytesObserved);
        assertEquals(1L, snapshot.oversizeFrameCount);
        assertEquals(2L, snapshot.invalidFrameLengthCount);
    }

    private static void testFrameAllocationMetrics() {
        FrameAllocationMetrics metrics = new FrameAllocationMetrics();
        metrics.recordTransportFrame(1_024, true);
        metrics.recordTransportFrame(2_048, true);
        FrameAllocationMetrics.Snapshot first = metrics.snapshotAndResetWindow();
        assertEquals(3_072L, first.allocatedFrameBytes);
        assertEquals(2L, first.bufferReuseCount);
        assertEquals(2L, first.bufferPoolMiss);
        FrameAllocationMetrics.Snapshot second = metrics.snapshotAndResetWindow();
        assertEquals(0L, second.allocatedFrameBytes);
        assertEquals(0L, second.bufferReuseCount);
        assertEquals(0L, second.bufferPoolMiss);
    }

    private static void testProtocolV2SessionFiltering() {
        ReceiverProtocolSession session = new ReceiverProtocolSession();
        session.onConnected(3);
        assertTrue(session.acceptStreamConfig(3, 2, 8, 12));
        assertTrue(session.isNegotiatedV2());
        assertTrue(session.matchesIdentity(8, 12));
        assertFalse(session.matchesIdentity(8, 11));
        assertTrue(session.acceptFrame(3, telemetry(8, 12, 1)));
        assertEquals(AndroidDropReason.STALE_CONNECTION_GENERATION,
                session.frameRejectionReason(2, telemetry(8, 12, 2)));
        assertEquals(AndroidDropReason.STALE_SESSION_EPOCH,
                session.frameRejectionReason(3, telemetry(7, 12, 3)));
        assertEquals(AndroidDropReason.STALE_CONFIG_VERSION,
                session.frameRejectionReason(3, telemetry(8, 11, 4)));
        assertEquals(AndroidDropReason.STALE_CONFIG_VERSION,
                session.frameRejectionReason(3, telemetry(8, 12, 1)));
        assertFalse(session.acceptFrame(2, telemetry(8, 12, 2)));
        assertFalse(session.acceptFrame(3, telemetry(7, 12, 3)));
        assertFalse(session.acceptFrame(3, telemetry(8, 11, 4)));
        assertFalse(session.acceptFrame(3, telemetry(8, 12, 1)));
        assertTrue(session.acceptFrame(3, telemetry(8, 12, 2)));
        assertFalse(session.acceptStreamConfig(3, 1, 0, 0));
        assertTrue(session.isNegotiatedV2());
        assertFalse(session.acceptStreamConfig(3, 2, 7, 13));
        assertFalse(session.acceptStreamConfig(3, 2, 8, 12));
        assertTrue(session.acceptStreamConfig(3, 2, 8, 13));
        assertFalse(session.matchesIdentity(8, 12));
        assertTrue(session.matchesIdentity(8, 13));
        assertFalse(session.acceptFrame(3, telemetry(8, 12, 3)));
        assertTrue(session.acceptFrame(3, telemetry(8, 13, 1)));

        session.onConnected(4);
        assertEquals(AndroidDropReason.CODEC_RECONFIGURE_DROP,
                session.frameRejectionReason(4, telemetry(8, 12, 3)));
        assertFalse(session.acceptFrame(4, telemetry(8, 12, 3)));
        assertTrue(session.acceptStreamConfig(4, 1, 0, 0));
        assertFalse(session.isNegotiatedV2());
        assertTrue(session.matchesIdentity(0, 0));
        assertTrue(session.acceptFrame(4, VideoFrameTelemetry.fromWirePayload(
                new byte[] {0, 0, 0, 1, 0x65}, 5)));
    }

    private static VideoFrameTelemetry telemetry(long epoch, long version, long sequence) {
        byte[] payload = concat(
                ("{\"cap\":1,\"snd\":2,\"se\":" + epoch + ",\"cv\":" + version
                        + ",\"fs\":" + sequence + "}").getBytes(StandardCharsets.UTF_8),
                new byte[] {0, 0, 0, 1, 0x65});
        return VideoFrameTelemetry.fromWirePayload(payload, 3);
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
        assertTrue(VideoFrameClassifier.isKeyframe(annexB((byte) 0x65), h264));
        assertFalse(VideoFrameClassifier.isKeyframe(annexB((byte) 0x67), h264));
        assertFalse(VideoFrameClassifier.isImportant(annexB((byte) 0x41), h264));

        VideoStreamConfig hevc = VideoStreamConfig.from("hevc", 120, 2560, 1600, 0);
        assertTrue(VideoFrameClassifier.isImportant(
                hevcAnnexB(32, 33, 19), hevc));
        assertTrue(VideoFrameClassifier.isKeyframe(hevcAnnexB(19), hevc));
        assertTrue(VideoFrameClassifier.isKeyframe(hevcAnnexB(20), hevc));
        assertFalse(VideoFrameClassifier.isKeyframe(hevcAnnexB(32), hevc));
        assertFalse(VideoFrameClassifier.isImportant(hevcAnnexB(1), hevc));
    }

    private static void testVideoFramePacketUsesZeroCopyBinaryPayloadView() throws Exception {
        VideoStreamConfig h264 = VideoStreamConfig.from("h264", 60, 1920, 1080, 0);
        byte[] annexB = annexB((byte) 0x67, (byte) 0x68, (byte) 0x65);
        byte[] binary = BinaryFrameHeaderV2.encode(
                BinaryFrameHeaderV2.FLAG_KEYFRAME
                        | BinaryFrameHeaderV2.FLAG_CODEC_CONFIG
                        | BinaryFrameHeaderV2.FLAG_H264,
                8, 12, 44, 1_000, 1_010, annexB);
        VideoFramePacket packet = VideoFramePacket.parse(binary, 2_000, h264);
        assertTrue(packet.bytes == binary);
        assertEquals(BinaryFrameHeaderV2.HEADER_BYTES, packet.payloadOffset);
        assertEquals(annexB.length, packet.payloadLength);
        assertTrue(packet.binaryHeaderV2);
        assertTrue(packet.keyframe);
        assertTrue(packet.codecConfig);
        assertTrue(packet.isImportant());
        assertTrue(packet.codecMatches(h264));
        assertFalse(packet.codecMatches(
                VideoStreamConfig.from("hevc", 60, 1920, 1080, 0)));
        assertEquals(8L, packet.telemetry.sessionEpoch);
        assertEquals(12L, packet.telemetry.configVersion);
        assertEquals(44L, packet.telemetry.frameSequence);
        assertTrue(packet.nalSummary(h264).source == binary);

        byte[] legacy = concat(
                "{\"cap\":1000,\"snd\":1010}".getBytes(StandardCharsets.UTF_8),
                annexB);
        VideoFramePacket legacyPacket = VideoFramePacket.parse(legacy, 2_000, h264);
        assertTrue(legacyPacket.bytes == legacy);
        assertFalse(legacyPacket.binaryHeaderV2);
        assertTrue(legacyPacket.payloadOffset > 0);
        assertTrue(legacyPacket.nalSummary(h264).source == legacy);
        assertTrue(legacyPacket.keyframe);
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

    private static void testDecoderStallRecoveryPolicy() {
        assertFalse(DecoderStallRecoveryPolicy.shouldRecover(
                10_000, 9_500, 9_400, 0));
        assertTrue(DecoderStallRecoveryPolicy.shouldRecover(
                10_000, 9_500, 7_500, 0));
        assertFalse(DecoderStallRecoveryPolicy.shouldRecover(
                10_000, 7_000, 7_500, 0));
        assertFalse(DecoderStallRecoveryPolicy.shouldRecover(
                10_000, 9_500, 7_500, 9_000));
    }

    private static void testDecoderReconfigurationPolicy() {
        VideoStreamConfig current = VideoStreamConfig.from(
                "hevc", 120, 3040, 1904, 80_000_000);
        VideoStreamConfig bitrateOnly = VideoStreamConfig.from(
                "hevc", 120, 3040, 1904, 64_000_000);
        assertFalse(DecoderReconfigurationPolicy.requiresReplacement(current, bitrateOnly));

        assertTrue(DecoderReconfigurationPolicy.requiresReplacement(
                current, VideoStreamConfig.from("h264", 120, 3040, 1904, 64_000_000)));
        assertTrue(DecoderReconfigurationPolicy.requiresReplacement(
                current, VideoStreamConfig.from("hevc", 60, 3040, 1904, 64_000_000)));
        assertTrue(DecoderReconfigurationPolicy.requiresReplacement(
                current, VideoStreamConfig.from("hevc", 120, 2280, 1428, 64_000_000)));
    }

    private static void testDecoderLowLatencyMode() {
        assertEquals(DecoderLowLatencyMode.AUTO,
                DecoderLowLatencyMode.fromStoredValue(null));
        assertEquals(DecoderLowLatencyMode.AUTO,
                DecoderLowLatencyMode.fromStoredValue("unexpected"));
        assertEquals(DecoderLowLatencyMode.ON,
                DecoderLowLatencyMode.fromStoredValue("on"));
        assertEquals(DecoderLowLatencyMode.OFF,
                DecoderLowLatencyMode.fromStoredValue("off"));
        assertTrue(DecoderLowLatencyMode.AUTO.requestsLowLatency());
        assertTrue(DecoderLowLatencyMode.ON.requestsLowLatency());
        assertFalse(DecoderLowLatencyMode.OFF.requestsLowLatency());
    }

    private static void testDecoderSelectionAndFallbackOrder() {
        List<DecoderSelectionPolicy.Candidate> candidates = java.util.Arrays.asList(
                new DecoderSelectionPolicy.Candidate(
                        "c2.android.hevc.decoder", false, true, false, true),
                new DecoderSelectionPolicy.Candidate(
                        "c2.vendor.hevc.decoder", true, false, true, false),
                new DecoderSelectionPolicy.Candidate(
                        "c2.vendor.hevc.low_latency", true, false, true, true));

        List<DecoderSelectionPolicy.Attempt> automatic =
                DecoderSelectionPolicy.attempts(candidates, DecoderLowLatencyMode.AUTO);
        assertEquals(5, automatic.size());
        assertEquals("c2.vendor.hevc.low_latency", automatic.get(0).decoderName);
        assertTrue(automatic.get(0).enableLowLatency);
        assertEquals("c2.vendor.hevc.low_latency", automatic.get(1).decoderName);
        assertFalse(automatic.get(1).enableLowLatency);
        assertEquals("c2.vendor.hevc.decoder", automatic.get(2).decoderName);
        assertFalse(automatic.get(2).enableLowLatency);
        assertEquals("c2.android.hevc.decoder", automatic.get(3).decoderName);
        assertTrue(automatic.get(3).enableLowLatency);
        assertEquals("c2.android.hevc.decoder", automatic.get(4).decoderName);
        assertFalse(automatic.get(4).enableLowLatency);

        List<DecoderSelectionPolicy.Attempt> disabled =
                DecoderSelectionPolicy.attempts(candidates, DecoderLowLatencyMode.OFF);
        assertEquals(3, disabled.size());
        assertEquals("c2.vendor.hevc.decoder", disabled.get(0).decoderName);
        for (DecoderSelectionPolicy.Attempt attempt : disabled) {
            assertFalse(attempt.enableLowLatency);
        }
    }

    private static void testDecoderRuntimeFailureMetrics() {
        DecoderRuntimeInfo failure = new DecoderRuntimeInfo(
                "hevc", "c2.vendor.hevc.decoder", true, false, true,
                true, false, false,
                "decoderConfigureFailed:c2.vendor.hevc.decoder:CodecException");
        assertFalse(failure.configureSuccess);
        assertFalse(failure.lowLatencyEnabled);
        assertEquals("decoderConfigureFailed:c2.vendor.hevc.decoder:CodecException",
                failure.fallbackReason);
    }

    private static void testWifiLowLatencyLifecycle() {
        final class FakeLock implements WifiLowLatencyLifecycle.LockAdapter {
            int acquireCount;
            int releaseCount;
            boolean held;

            @Override
            public boolean acquire() {
                acquireCount++;
                held = true;
                return true;
            }

            @Override
            public boolean release() {
                releaseCount++;
                held = false;
                return true;
            }

            @Override
            public boolean isHeld() {
                return held;
            }
        }

        assertEquals(WifiLowLatencyMode.AUTO,
                WifiLowLatencyMode.fromStoredValue(null));
        assertEquals(WifiLowLatencyMode.ON,
                WifiLowLatencyMode.fromStoredValue("on"));
        assertEquals(WifiLowLatencyMode.OFF,
                WifiLowLatencyMode.fromStoredValue("off"));

        FakeLock lock = new FakeLock();
        WifiLowLatencyLifecycle lifecycle = new WifiLowLatencyLifecycle(29, lock);
        lifecycle.update(WifiLowLatencyMode.AUTO,
                true, true, true, "wifi");
        assertTrue(lifecycle.snapshot().requested);
        assertTrue(lifecycle.snapshot().acquired);
        assertTrue(lifecycle.snapshot().active);
        assertEquals(1, lock.acquireCount);

        lifecycle.update(WifiLowLatencyMode.AUTO,
                true, true, true, "wifi");
        assertEquals(1, lock.acquireCount);

        lifecycle.update(WifiLowLatencyMode.AUTO,
                true, true, true, "android-adb-usb");
        assertFalse(lifecycle.snapshot().active);
        assertEquals("transportNotWifi", lifecycle.snapshot().releaseReason);
        assertEquals(1, lock.releaseCount);

        lifecycle.update(WifiLowLatencyMode.ON,
                true, true, true, "wifi");
        assertEquals(2, lock.acquireCount);
        lifecycle.update(WifiLowLatencyMode.ON,
                false, true, true, "wifi");
        assertEquals("appBackground", lifecycle.snapshot().releaseReason);
        assertEquals(2, lock.releaseCount);

        lifecycle.update(WifiLowLatencyMode.OFF,
                true, true, true, "wifi");
        assertFalse(lifecycle.snapshot().requested);
        assertFalse(lifecycle.snapshot().active);
        assertEquals("disabledByUser", lifecycle.snapshot().releaseReason);

        FakeLock unsupportedLock = new FakeLock();
        WifiLowLatencyLifecycle unsupported =
                new WifiLowLatencyLifecycle(28, unsupportedLock);
        unsupported.update(WifiLowLatencyMode.ON,
                true, true, true, "wifi");
        assertEquals(0, unsupportedLock.acquireCount);
        assertEquals("unsupportedApi", unsupported.snapshot().releaseReason);

        lifecycle.update(WifiLowLatencyMode.AUTO,
                true, true, true, "wifi");
        lifecycle.shutdown("activityDestroyed");
        assertFalse(lifecycle.snapshot().active);
        assertEquals("activityDestroyed", lifecycle.snapshot().releaseReason);
        assertEquals(3, lock.releaseCount);
    }

    private static void testSurfaceFrameRateLifecycle() {
        final int[] applyCount = {0};
        final int[] clearCount = {0};
        final int[] lastFps = {0};
        final String[] lastReason = {""};
        SurfaceFrameRateLifecycle lifecycle = new SurfaceFrameRateLifecycle(
                new SurfaceFrameRateLifecycle.Actions() {
                    @Override
                    public void apply(int fps, String reason) {
                        applyCount[0]++;
                        lastFps[0] = fps;
                        lastReason[0] = reason;
                    }

                    @Override
                    public void clear(String reason) {
                        clearCount[0]++;
                        lastReason[0] = reason;
                    }
                });

        lifecycle.onResume();
        assertEquals(0, applyCount[0]);
        lifecycle.onSurfaceCreated();
        assertEquals(1, applyCount[0]);
        assertEquals(60, lastFps[0]);
        assertEquals("surfaceCreated", lastReason[0]);

        lifecycle.onStreamConfig(120);
        assertEquals(2, applyCount[0]);
        assertEquals(120, lastFps[0]);
        lifecycle.onDecoderRebuild();
        assertEquals(3, applyCount[0]);
        assertEquals("decoderRebuild", lastReason[0]);

        lifecycle.onStreamingStopped();
        assertEquals(1, clearCount[0]);
        lifecycle.onStreamingStopped();
        assertEquals(1, clearCount[0]);
        lifecycle.onStreamingStarted();
        assertEquals(4, applyCount[0]);
        assertEquals("streamingStarted", lastReason[0]);

        lifecycle.onPause();
        assertEquals(2, clearCount[0]);
        assertEquals("appBackground", lastReason[0]);
        lifecycle.onResume();
        assertEquals(5, applyCount[0]);
        assertEquals("foregroundResume", lastReason[0]);
        lifecycle.onSurfaceDestroyed();
        assertEquals(3, clearCount[0]);
        lifecycle.onDestroy();
        assertEquals(3, clearCount[0]);
    }

    private static void testAndroidDropReasonClassification() {
        assertEquals(15, AndroidDropReason.values().length);
        assertTrue(AndroidDropReason.LATEST_SLOT_REPLACED.congestionRelevant);
        assertTrue(AndroidDropReason.DECODER_INPUT_UNAVAILABLE.congestionRelevant);
        assertTrue(AndroidDropReason.FRAME_AGE_EXPIRED.congestionRelevant);
        assertFalse(AndroidDropReason.SURFACE_UNAVAILABLE.congestionRelevant);
        assertFalse(AndroidDropReason.STALE_CONNECTION_GENERATION.congestionRelevant);
        assertFalse(AndroidDropReason.STALE_SESSION_EPOCH.congestionRelevant);
        assertFalse(AndroidDropReason.STALE_CONFIG_VERSION.congestionRelevant);
        assertFalse(AndroidDropReason.CODEC_RECONFIGURE_DROP.congestionRelevant);

        AndroidDropTracker tracker = new AndroidDropTracker();
        AndroidDropTracker.Context context = new AndroidDropTracker.Context(
                3, 8, 12, 44, "hevc", "wifi");
        tracker.record(AndroidDropReason.SURFACE_UNAVAILABLE, context);
        tracker.record(AndroidDropReason.DECODER_INPUT_UNAVAILABLE, context);
        tracker.record(AndroidDropReason.DECODER_INPUT_UNAVAILABLE, context);

        AndroidDropTracker.Snapshot first = tracker.snapshotAndResetWindow();
        assertEquals(1L, first.windowCount(AndroidDropReason.SURFACE_UNAVAILABLE));
        assertEquals(2L, first.windowCount(AndroidDropReason.DECODER_INPUT_UNAVAILABLE));
        assertEquals(2L, first.congestionRelevantWindowCount);
        assertEquals(3L, first.totalDropCount);
        assertEquals("decoderInputUnavailable", first.lastEvent.reason);
        assertEquals(2L, first.lastEvent.countWindow);
        assertEquals(2L, first.lastEvent.countTotal);
        assertEquals(3L, first.lastEvent.generation);
        assertEquals(8L, first.lastEvent.sessionEpoch);
        assertEquals(12L, first.lastEvent.configVersion);
        assertEquals(44L, first.lastEvent.frameSequence);
        assertEquals("hevc", first.lastEvent.codec);
        assertEquals("wifi", first.lastEvent.transport);

        AndroidDropTracker.Snapshot second = tracker.snapshotAndResetWindow();
        assertEquals(0L, second.windowDropCount);
        assertEquals(3L, second.totalDropCount);
        assertEquals(2L, second.totalCount(
                AndroidDropReason.DECODER_INPUT_UNAVAILABLE));
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
        ClockOffsetEstimator estimating = new ClockOffsetEstimator(4);
        estimating.addSample(1000, 1012, 1014, 1006);
        assertEquals(null, OpenDisplayServer.stableOffsetOrNull(estimating));
        estimating.addSample(2000, 2014, 2016, 2008);
        estimating.addSample(3000, 3014, 3016, 3010);
        assertEquals(11.0, OpenDisplayServer.stableOffsetOrNull(estimating));
        estimating.reset();
        assertEquals(0, estimating.sampleCount());
        assertEquals(ClockOffsetEstimator.State.ESTIMATING, estimating.state());
        assertEquals(ClockOffsetEstimator.MISSING_MS, estimating.offsetMs());
        assertEquals(null, OpenDisplayServer.stableOffsetOrNull(estimating));
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
        OpenDisplayServer.MacPingMetrics overflow = OpenDisplayServer.MacPingMetrics.parse(
                "{\"inp50\":1e999,\"inp95\":NaN,\"requestedFps\":1e999}",
                4.0, 9.0, 60);
        assertEquals(4.0, overflow.inputP50Ms);
        assertEquals(9.0, overflow.inputP95Ms);
        assertEquals(60, overflow.requestedFps);
    }

    private static void testWifiTransportCarriesFramedPayloads() {
        WifiTcpReceiverTransport transport = new WifiTcpReceiverTransport(0);
        AtomicInteger listeningPort = new AtomicInteger();
        AtomicReference<byte[]> received = new AtomicReference<>();
        AtomicLong generation = new AtomicLong();
        CountDownLatch listening = new CountDownLatch(1);
        CountDownLatch connected = new CountDownLatch(1);
        CountDownLatch payloadReceived = new CountDownLatch(1);

        transport.start(new ReceiverTransport.Listener() {
            @Override public void onListening(int port) {
                listeningPort.set(port);
                listening.countDown();
            }
            @Override public void onConnected(long nextGeneration, String peer) {
                generation.set(nextGeneration);
                connected.countDown();
            }
            @Override public void onPayload(long payloadGeneration, byte[] payload) {
                assertEquals(generation.get(), payloadGeneration);
                received.set(payload);
                payloadReceived.countDown();
            }
            @Override public void onDisconnected(long disconnectedGeneration) { }
            @Override public void onError(long errorGeneration, String message) {
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

                transport.send(generation.get(), "from-android".getBytes(StandardCharsets.UTF_8));
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

    private static void testAcceptedSocketOptions() {
        try (Socket socket = new Socket()) {
            WifiTcpReceiverTransport.configureAcceptedSocket(socket);
            assertTrue(socket.getTcpNoDelay());
            assertTrue(socket.getKeepAlive());
        } catch (Exception error) {
            throw new AssertionError("accepted socket options failed", error);
        }
    }

    private static void testWifiTransportAcceptsV2FrameSize() {
        ReceiverTransport transport = new WifiTcpReceiverTransport(0);
        AtomicInteger listeningPort = new AtomicInteger();
        CountDownLatch listening = new CountDownLatch(1);
        CountDownLatch connected = new CountDownLatch(1);
        CountDownLatch received = new CountDownLatch(1);
        int frameBytes = LengthPrefixedProtocol.LEGACY_MAX_FRAME_BYTES + 1;

        transport.start(new ReceiverTransport.Listener() {
            @Override public void onListening(int port) {
                listeningPort.set(port);
                listening.countDown();
            }
            @Override public void onConnected(long generation, String peer) {
                connected.countDown();
            }
            @Override public void onPayload(long generation, byte[] payload) {
                if (LengthPrefixedProtocol.isPureJsonControl(payload)) {
                    return;
                }
                assertEquals(frameBytes, payload.length);
                received.countDown();
            }
            @Override public void onDisconnected(long generation) { }
            @Override public void onError(long generation, String message) { }
        });

        try {
            assertTrue(listening.await(2, TimeUnit.SECONDS));
            try (Socket client = new Socket("127.0.0.1", listeningPort.get())) {
                assertTrue(connected.await(2, TimeUnit.SECONDS));
                LengthPrefixedProtocol.write(
                        new BufferedOutputStream(client.getOutputStream()),
                        ("{\"type\":\"streamConfig\",\"protocolVersion\":2,"
                                + "\"maxFrameBytes\":8388608}")
                                .getBytes(StandardCharsets.UTF_8));
                LengthPrefixedProtocol.write(
                        new BufferedOutputStream(client.getOutputStream()),
                        new byte[frameBytes]);
                assertTrue(received.await(2, TimeUnit.SECONDS));
            }
        } catch (Exception error) {
            throw new AssertionError("V2 frame limit loopback failed", error);
        } finally {
            transport.stop();
        }
    }

    private static void testWifiTransportKeepsLegacyFrameLimit() {
        WifiTcpReceiverTransport transport = new WifiTcpReceiverTransport(0);
        AtomicInteger listeningPort = new AtomicInteger();
        AtomicInteger rejectedMaximum = new AtomicInteger();
        CountDownLatch listening = new CountDownLatch(1);
        CountDownLatch connected = new CountDownLatch(1);
        CountDownLatch rejected = new CountDownLatch(1);

        transport.start(new ReceiverTransport.Listener() {
            @Override public void onListening(int port) {
                listeningPort.set(port);
                listening.countDown();
            }
            @Override public void onConnected(long generation, String peer) {
                connected.countDown();
            }
            @Override public void onPayload(long generation, byte[] payload) { }
            @Override public void onFrameLengthRejected(
                    long generation, String reason, int frameBytes, int maximumBytes) {
                rejectedMaximum.set(maximumBytes);
                rejected.countDown();
            }
            @Override public void onDisconnected(long generation) { }
            @Override public void onError(long generation, String message) { }
        });

        try {
            assertTrue(listening.await(2, TimeUnit.SECONDS));
            try (Socket client = new Socket("127.0.0.1", listeningPort.get())) {
                assertTrue(connected.await(2, TimeUnit.SECONDS));
                LengthPrefixedProtocol.write(
                        new BufferedOutputStream(client.getOutputStream()),
                        "{\"type\":\"streamConfig\"}"
                                .getBytes(StandardCharsets.UTF_8));
                byte[] header = java.nio.ByteBuffer.allocate(4)
                        .order(java.nio.ByteOrder.BIG_ENDIAN)
                        .putInt(LengthPrefixedProtocol.LEGACY_MAX_FRAME_BYTES + 1)
                        .array();
                client.getOutputStream().write(header);
                client.getOutputStream().flush();
                assertTrue(rejected.await(2, TimeUnit.SECONDS));
                assertEquals(LengthPrefixedProtocol.LEGACY_MAX_FRAME_BYTES,
                        rejectedMaximum.get());
            }
        } catch (Exception error) {
            throw new AssertionError("legacy frame limit loopback failed", error);
        } finally {
            transport.stop();
        }
    }

    private static void testWifiTransportRejectsOversizeWithReason() {
        ReceiverTransport transport = new WifiTcpReceiverTransport(0);
        AtomicInteger listeningPort = new AtomicInteger();
        AtomicReference<String> rejectedReason = new AtomicReference<>();
        AtomicInteger rejectedLength = new AtomicInteger();
        CountDownLatch listening = new CountDownLatch(1);
        CountDownLatch connected = new CountDownLatch(1);
        CountDownLatch rejected = new CountDownLatch(1);
        CountDownLatch disconnected = new CountDownLatch(1);

        transport.start(new ReceiverTransport.Listener() {
            @Override public void onListening(int port) {
                listeningPort.set(port);
                listening.countDown();
            }
            @Override public void onConnected(long generation, String peer) {
                connected.countDown();
            }
            @Override public void onPayload(long generation, byte[] payload) { }
            @Override public void onFrameLengthRejected(
                    long generation, String reason, int frameBytes, int maximumBytes) {
                rejectedReason.set(reason);
                rejectedLength.set(frameBytes);
                assertEquals(LengthPrefixedProtocol.V2_DEFAULT_MAX_FRAME_BYTES, maximumBytes);
                rejected.countDown();
            }
            @Override public void onDisconnected(long generation) {
                disconnected.countDown();
            }
            @Override public void onError(long generation, String message) { }
        });

        try {
            assertTrue(listening.await(2, TimeUnit.SECONDS));
            try (Socket client = new Socket("127.0.0.1", listeningPort.get())) {
                assertTrue(connected.await(2, TimeUnit.SECONDS));
                LengthPrefixedProtocol.write(
                        new BufferedOutputStream(client.getOutputStream()),
                        ("{\"type\":\"streamConfig\",\"protocolVersion\":2,"
                                + "\"maxFrameBytes\":8388608}")
                                .getBytes(StandardCharsets.UTF_8));
                int length = LengthPrefixedProtocol.V2_DEFAULT_MAX_FRAME_BYTES + 1;
                byte[] header = java.nio.ByteBuffer.allocate(4)
                        .order(java.nio.ByteOrder.BIG_ENDIAN).putInt(length).array();
                client.getOutputStream().write(header);
                client.getOutputStream().flush();
                assertTrue(rejected.await(2, TimeUnit.SECONDS));
                assertTrue(disconnected.await(2, TimeUnit.SECONDS));
                assertEquals("oversize", rejectedReason.get());
                assertEquals(length, rejectedLength.get());
            }
        } catch (Exception error) {
            throw new AssertionError("oversize frame rejection failed", error);
        } finally {
            transport.stop();
        }
    }

    private static void testWifiTransportReplacesBlockedConnection() {
        WifiTcpReceiverTransport transport = new WifiTcpReceiverTransport(0);
        AtomicInteger listeningPort = new AtomicInteger();
        AtomicInteger connectionCount = new AtomicInteger();
        List<Long> generations = new CopyOnWriteArrayList<>();
        List<Long> disconnected = new CopyOnWriteArrayList<>();
        AtomicLong payloadGeneration = new AtomicLong();
        CountDownLatch listening = new CountDownLatch(1);
        CountDownLatch firstConnected = new CountDownLatch(1);
        CountDownLatch secondConnected = new CountDownLatch(1);
        CountDownLatch secondPayload = new CountDownLatch(1);
        CountDownLatch currentDisconnected = new CountDownLatch(1);

        transport.start(new ReceiverTransport.Listener() {
            @Override public void onListening(int port) {
                listeningPort.set(port);
                listening.countDown();
            }
            @Override public void onConnected(long generation, String peer) {
                generations.add(generation);
                if (connectionCount.incrementAndGet() == 1) {
                    firstConnected.countDown();
                } else {
                    secondConnected.countDown();
                }
            }
            @Override public void onPayload(long generation, byte[] payload) {
                payloadGeneration.set(generation);
                secondPayload.countDown();
            }
            @Override public void onDisconnected(long generation) {
                disconnected.add(generation);
                currentDisconnected.countDown();
            }
            @Override public void onError(long generation, String message) {
                // Closing the current client at the end of the test may report an EOF first.
            }
        });

        try {
            assertTrue(listening.await(2, TimeUnit.SECONDS));
            try (Socket first = new Socket("127.0.0.1", listeningPort.get())) {
                first.setSoTimeout(2000);
                assertTrue(firstConnected.await(2, TimeUnit.SECONDS));
                try (Socket second = new Socket("127.0.0.1", listeningPort.get())) {
                    second.setSoTimeout(2000);
                    assertTrue(secondConnected.await(2, TimeUnit.SECONDS));
                    assertEquals(2, generations.size());
                    assertTrue(generations.get(1) > generations.get(0));
                    assertEquals(generations.get(1).longValue(), transport.currentGeneration());

                    int oldRead;
                    try {
                        oldRead = first.getInputStream().read();
                    } catch (java.net.SocketException closedByPeer) {
                        oldRead = -1;
                    }
                    assertEquals(-1, oldRead);

                    long oldGeneration = generations.get(0);
                    long currentGeneration = generations.get(1);
                    transport.send(oldGeneration, "stale-write".getBytes(StandardCharsets.UTF_8));
                    transport.send(currentGeneration, "current-write".getBytes(StandardCharsets.UTF_8));
                    byte[] reply = LengthPrefixedProtocol.read(
                            new BufferedInputStream(second.getInputStream()));
                    assertEquals("current-write", new String(reply, StandardCharsets.UTF_8));

                    BufferedOutputStream output = new BufferedOutputStream(second.getOutputStream());
                    LengthPrefixedProtocol.write(output, "new-payload".getBytes(StandardCharsets.UTF_8));
                    output.flush();
                    assertTrue(secondPayload.await(2, TimeUnit.SECONDS));
                    assertEquals(currentGeneration, payloadGeneration.get());
                    assertTrue(disconnected.isEmpty());
                }
                assertTrue(currentDisconnected.await(2, TimeUnit.SECONDS));
                assertEquals(1, disconnected.size());
                assertEquals(generations.get(1), disconnected.get(0));
            }
        } catch (Exception error) {
            throw new AssertionError("connection generation takeover failed", error);
        } finally {
            transport.stop();
        }
    }

    private static void testWifiTransportIgnoresSendAfterStop() {
        ReceiverTransport transport = new WifiTcpReceiverTransport(0);
        transport.stop();
        try {
            transport.send(1, "late-ping".getBytes(StandardCharsets.UTF_8));
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

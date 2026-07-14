package app.opendisplay.android.protocol;

import java.io.ByteArrayInputStream;
import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.util.ArrayList;
import java.util.List;
import java.util.LinkedHashMap;
import java.util.Map;

import app.opendisplay.android.ControlMessageWriter;
import app.opendisplay.android.ReceiverStatsSnapshot;
import app.opendisplay.android.ScrollGestureTracker;
import app.opendisplay.android.TouchGestureCoordinator;
import app.opendisplay.android.TouchEventMapper;

public final class ProtocolSelfTest {
    public static void main(String[] args) throws Exception {
        testLengthPrefixedRoundTrip();
        testNegotiatedFrameSizeLimits();
        testJsonClassification();
        testHelloJsonIncludesDisplayCapabilities();
        testHelloJsonAdvertisesNegotiatedProtocolV2();
        testStreamConfigJson();
        testProtocolV2ProgressMessages();
        testDecoderResetRequestPreservesLegacyAndRequestsFreshV2Config();
        testGoodbyeJson();
        testReceiverStatsJsonUsesCanonicalFieldsAndNulls();
        testStatsJsonRejectsNonFiniteNumbers();
        testAnnexBTelemetryAndNalus();
        testAnnexBFindsHevcParameterSets();
        testSpsParser();
        testMacCursorControlMessage();
        testTouchPointerIndexIsSafe();
        testScrollJson();
        testScrollGestureTrackerProducesPixelDeltas();
        testTouchGestureCoordinatorDefersTapUntilGestureIsKnown();
        testTouchGestureCoordinatorCancelsPendingTapForScroll();
        testControlMessageWriterDoesNotWriteOnCallerThread();
        System.out.println("ProtocolSelfTest PASS");
    }

    private static void testLengthPrefixedRoundTrip() throws Exception {
        byte[] encoded = LengthPrefixedProtocol.encode("hello".getBytes("UTF-8"));
        byte[] decoded = LengthPrefixedProtocol.read(new ByteArrayInputStream(encoded));
        assertEquals("hello", new String(decoded, "UTF-8"));
    }

    private static void testNegotiatedFrameSizeLimits() throws Exception {
        int largerThanLegacy = LengthPrefixedProtocol.LEGACY_MAX_FRAME_BYTES + 1;
        byte[] payload = new byte[largerThanLegacy];
        byte[] framed = LengthPrefixedProtocol.encode(payload);

        assertFrameLengthFailure(
                framed,
                LengthPrefixedProtocol.LEGACY_MAX_FRAME_BYTES,
                LengthPrefixedProtocol.FrameLengthFailure.OVERSIZE);
        assertEquals(largerThanLegacy,
                LengthPrefixedProtocol.read(
                        new ByteArrayInputStream(framed),
                        LengthPrefixedProtocol.V2_DEFAULT_MAX_FRAME_BYTES).length);

        assertFrameLengthFailure(
                lengthHeader(LengthPrefixedProtocol.V2_DEFAULT_MAX_FRAME_BYTES + 1),
                LengthPrefixedProtocol.V2_DEFAULT_MAX_FRAME_BYTES,
                LengthPrefixedProtocol.FrameLengthFailure.OVERSIZE);
        assertFrameLengthFailure(
                lengthHeader(LengthPrefixedProtocol.ABSOLUTE_MAX_FRAME_BYTES + 1),
                LengthPrefixedProtocol.ABSOLUTE_MAX_FRAME_BYTES,
                LengthPrefixedProtocol.FrameLengthFailure.ABSOLUTE_LIMIT);
        assertFrameLengthFailure(
                lengthHeader(0),
                LengthPrefixedProtocol.V2_DEFAULT_MAX_FRAME_BYTES,
                LengthPrefixedProtocol.FrameLengthFailure.INVALID_LENGTH);
        assertEquals(LengthPrefixedProtocol.LEGACY_MAX_FRAME_BYTES,
                LengthPrefixedProtocol.streamConfigFrameLimit(
                        "{\"type\":\"streamConfig\"}".getBytes("UTF-8")));
        assertEquals(LengthPrefixedProtocol.V2_DEFAULT_MAX_FRAME_BYTES,
                LengthPrefixedProtocol.streamConfigFrameLimit(
                        ("{\"type\":\"streamConfig\",\"protocolVersion\":2,"
                                + "\"maxFrameBytes\":8388608}").getBytes("UTF-8")));
        assertEquals(-1, LengthPrefixedProtocol.streamConfigFrameLimit(
                "{\"type\":\"ping\"}".getBytes("UTF-8")));
    }

    private static void testJsonClassification() {
        assertTrue(LengthPrefixedProtocol.isPureJsonControl("{\"type\":\"ping\"}".getBytes()));
        assertFalse(LengthPrefixedProtocol.isPureJsonControl(new byte[] {'{', 0, 0, 0, 1, 0x65}));
    }

    private static void testHelloJsonIncludesDisplayCapabilities() {
        String json = LengthPrefixedProtocol.helloJson(
                2560,
                1600,
                2.0,
                120,
                120,
                new String[] {"hevc", "h264"},
                "hevc",
                "Android Tablet",
                35,
                "wifi",
                "Android",
                "install-1");
        assertContains(json, "\"type\":\"hello\"");
        assertContains(json, "\"pixelsWide\":2560");
        assertContains(json, "\"pixelsHigh\":1600");
        assertContains(json, "\"scale\":2.000");
        assertContains(json, "\"refreshRate\":120");
        assertContains(json, "\"maxFps\":120");
        assertContains(json, "\"supportedCodecs\":[\"hevc\",\"h264\"]");
        assertContains(json, "\"preferredCodec\":\"hevc\"");
        assertContains(json, "\"deviceModel\":\"Android Tablet\"");
        assertContains(json, "\"androidSdk\":35");
        assertContains(json, "\"transport\":\"wifi\"");
        assertContains(json, "\"device\":\"Android\"");
        assertContains(json, "\"id\":\"install-1\"");
    }

    private static void testHelloJsonAdvertisesNegotiatedProtocolV2() {
        String json = LengthPrefixedProtocol.helloJson(
                2560, 1600, 2.0, 120, 120,
                new String[] {"hevc", "h264"}, "hevc", "Android Tablet", 35,
                "wifi", "Android", "install-1");
        assertContains(json, "\"protocolVersion\":2");
        assertContains(json, "\"maxFrameBytes\":8388608");
        assertContains(json, "\"capabilities\":[\"streamConfigAck\",\"decoderReady\","
                + "\"firstFrameRendered\",\"sessionEpoch\",\"configVersion\","
                + "\"frameSequence\",\"maxFrameBytes\"]");
    }

    private static void testProtocolV2ProgressMessages() {
        String ack = LengthPrefixedProtocol.streamConfigAckJson(
                8, 12, true, "hevc", 120, 2560, 1600, true);
        assertContains(ack, "\"type\":\"streamConfigAck\"");
        assertContains(ack, "\"sessionEpoch\":8");
        assertContains(ack, "\"configVersion\":12");
        assertContains(ack, "\"accepted\":true");
        assertContains(ack, "\"surfaceValid\":true");

        String ready = LengthPrefixedProtocol.decoderReadyJson(
                8, 12, "hevc", "c2.vendor.hevc.decoder", true,
                false, true, true, true, true, "");
        assertContains(ready, "\"type\":\"decoderReady\"");
        assertContains(ready, "\"decoderName\":\"c2.vendor.hevc.decoder\"");
        assertContains(ready, "\"hardwareAccelerated\":true");
        assertContains(ready, "\"vendor\":true");
        assertContains(ready, "\"lowLatencySupported\":true");
        assertContains(ready, "\"lowLatencyEnabled\":true");
        assertContains(ready, "\"configureSuccess\":true");

        String first = LengthPrefixedProtocol.firstFrameRenderedJson(8, 12, 41);
        assertContains(first, "\"type\":\"firstFrameRendered\"");
        assertContains(first, "\"frameSequence\":41");

        String state = LengthPrefixedProtocol.connectionStateJson(
                "WAITING_FIRST_FRAME", "decoderReady", 1234, 3, 8, 12);
        assertContains(state, "\"type\":\"connectionState\"");
        assertContains(state, "\"state\":\"waitingFirstFrame\"");
        assertContains(state, "\"reason\":\"decoderReady\"");
        assertContains(state, "\"enteredAt\":1234");
        assertContains(state, "\"generation\":3");
    }

    private static byte[] lengthHeader(int length) {
        return ByteBuffer.allocate(4).order(ByteOrder.BIG_ENDIAN).putInt(length).array();
    }

    private static void assertFrameLengthFailure(
            byte[] framed, int maximum, LengthPrefixedProtocol.FrameLengthFailure expected)
            throws Exception {
        try {
            LengthPrefixedProtocol.read(new ByteArrayInputStream(framed), maximum);
            throw new AssertionError("expected frame length failure " + expected);
        } catch (LengthPrefixedProtocol.FrameLengthException error) {
            assertEquals(expected.name(), error.failure.name());
            assertEquals(maximum, error.maximumBytes);
        } catch (IOException error) {
            throw new AssertionError("expected typed frame length failure", error);
        }
    }

    private static void testDecoderResetRequestPreservesLegacyAndRequestsFreshV2Config() {
        assertEquals("{\"type\":\"kf\"}",
                LengthPrefixedProtocol.decoderResetRequestJson(false));
        String negotiated = LengthPrefixedProtocol.decoderResetRequestJson(true);
        assertContains(negotiated, "\"type\":\"kf\"");
        assertContains(negotiated, "\"reason\":\"decoderReset\"");
        assertContains(negotiated, "\"streamConfigRequired\":true");
    }

    private static void testStreamConfigJson() {
        String json = LengthPrefixedProtocol.streamConfigJson(
                "hevc",
                120,
                2560,
                1600,
                60_000_000,
                "main",
                "wifi");
        assertContains(json, "\"type\":\"streamConfig\"");
        assertContains(json, "\"codec\":\"hevc\"");
        assertContains(json, "\"fps\":120");
        assertContains(json, "\"width\":2560");
        assertContains(json, "\"height\":1600");
        assertContains(json, "\"bitrate\":60000000");
        assertContains(json, "\"profile\":\"main\"");
        assertContains(json, "\"transport\":\"wifi\"");
    }

    private static void testGoodbyeJson() {
        assertEquals("{\"type\":\"goodbye\"}", LengthPrefixedProtocol.goodbyeJson());
    }

    private static void testReceiverStatsJsonUsesCanonicalFieldsAndNulls() {
        ReceiverStatsSnapshot snapshot = new ReceiverStatsSnapshot(
                1234L, "Pixel \"Tablet\"\\Pro", "usb", "hevc",
                2560, 1600, 120, 119.88,
                118, 117, 116, null,
                null, null, null, "estimating",
                8.25, 9L, 6L, 14L, 20L,
                null, null, 1, 2, 3.5, 7.5,
                2048, 4096, 3072, 6144, 2, 3,
                "c2.vendor.hevc.decoder", true, false, true,
                true, true, true, "", "auto");
        String json = snapshot.toJson();
        assertContains(json, "\"type\":\"stats\"");
        assertContains(json, "\"timestamp\":1234");
        assertContains(json, "\"deviceModel\":\"Pixel \\\"Tablet\\\"\\\\Pro\"");
        assertContains(json, "\"actualAndroidDisplayRefreshRate\":119.88");
        assertContains(json, "\"clockOffsetMs\":null");
        assertContains(json, "\"rttMs\":null");
        assertContains(json, "\"offsetConfidenceMs\":null");
        assertContains(json, "\"estimatedE2ELatencyMs\":null");
        assertContains(json, "\"sendToRenderEstimatedMs\":null");
        assertContains(json, "\"inputP95Ms\":7.5");
        assertContains(json, "\"currentFrameBytes\":2048");
        assertContains(json, "\"maxFrameBytesObserved\":4096");
        assertContains(json, "\"currentKeyframeBytes\":3072");
        assertContains(json, "\"maxKeyframeBytesObserved\":6144");
        assertContains(json, "\"oversizeFrameCount\":2");
        assertContains(json, "\"invalidFrameLengthCount\":3");
        assertContains(json, "\"decoderName\":\"c2.vendor.hevc.decoder\"");
        assertContains(json, "\"hardwareAccelerated\":true");
        assertContains(json, "\"lowLatencyEnabled\":true");
        assertContains(json, "\"decoderConfigureSuccess\":true");
        assertContains(json, "\"decoderLowLatencyMode\":\"auto\"");
        assertFalse(json.contains("\"null\""));
    }

    private static void testStatsJsonRejectsNonFiniteNumbers() {
        Map<String, Object> values = new LinkedHashMap<>();
        values.put("nan", Double.NaN);
        values.put("positiveInfinity", Double.POSITIVE_INFINITY);
        values.put("negativeInfinity", Float.NEGATIVE_INFINITY);
        String json = LengthPrefixedProtocol.statsJson(values);
        assertContains(json, "\"nan\":null");
        assertContains(json, "\"positiveInfinity\":null");
        assertContains(json, "\"negativeInfinity\":null");
        assertFalse(json.contains(":NaN"));
        assertFalse(json.contains(":Infinity"));
        assertFalse(json.contains(":-Infinity"));
    }

    private static void testAnnexBTelemetryAndNalus() throws Exception {
        byte[] prefix = "{\"cap\":1,\"snd\":2}".getBytes("UTF-8");
        byte[] frame = concat(prefix, new byte[] {0, 0, 0, 1, 0x67, 1, 2},
                new byte[] {0, 0, 0, 1, 0x68, 3, 4});
        assertEquals("{\"cap\":1,\"snd\":2}", AnnexB.telemetryPrefix(frame));
        assertEquals(2, AnnexB.nalUnits(frame).size());
        assertEquals(7, AnnexB.findNalUnit(frame, 7)[0] & 0x1F);
    }

    private static void testAnnexBFindsHevcParameterSets() throws Exception {
        byte[] prefix = "{\"cap\":1,\"snd\":2}".getBytes("UTF-8");
        byte[] frame = concat(prefix,
                new byte[] {0, 0, 0, 1, (byte) (32 << 1), 1},
                new byte[] {0, 0, 0, 1, (byte) (33 << 1), 1},
                new byte[] {0, 0, 0, 1, (byte) (34 << 1), 1},
                new byte[] {0, 0, 0, 1, (byte) (19 << 1), 1});
        assertEquals(32, (AnnexB.findNalUnit(frame, 32, true)[0] >> 1) & 0x3F);
        assertEquals(33, (AnnexB.findNalUnit(frame, 33, true)[0] >> 1) & 0x3F);
        assertEquals(34, (AnnexB.findNalUnit(frame, 34, true)[0] >> 1) & 0x3F);
    }

    private static void testSpsParser() {
        byte[] sps = buildBaselineSps(1280, 720);
        SpsParser.Size size = SpsParser.parseDimensions(sps);
        assertEquals(1280, size.width);
        assertEquals(720, size.height);
    }

    private static void testMacCursorControlMessage() {
        MacControlMessage cursor = MacControlMessage.parse(
                "{\"type\":\"cursor\",\"x\":0.2500,\"y\":0.7500,\"v\":1}");
        assertEquals("cursor", cursor.type);
        assertEquals(0.25, cursor.x);
        assertEquals(0.75, cursor.y);
        assertTrue(cursor.visible);

        MacControlMessage image = MacControlMessage.parse(
                "{\"type\":\"cursorImg\",\"nw\":0.01000,\"nh\":0.02000,\"ax\":0.100,\"ay\":0.200,\"png\":\"abcd\"}");
        assertEquals("cursorImg", image.type);
        assertEquals(0.01, image.normalizedWidth);
        assertEquals(0.02, image.normalizedHeight);
        assertEquals(0.1, image.anchorX);
        assertEquals(0.2, image.anchorY);
        assertEquals("abcd", image.pngBase64);
    }

    private static void testTouchPointerIndexIsSafe() {
        assertEquals(0, TouchEventMapper.safePointerIndex(TouchEventMapper.ACTION_MOVE, 2, 1));
        assertEquals(1, TouchEventMapper.safePointerIndex(TouchEventMapper.ACTION_UP, 99, 2));
        assertEquals(-1, TouchEventMapper.safePointerIndex(TouchEventMapper.ACTION_DOWN, 0, 0));
        assertEquals("moved", TouchEventMapper.phaseForAction(TouchEventMapper.ACTION_MOVE));
        assertEquals("ended", TouchEventMapper.phaseForAction(TouchEventMapper.ACTION_POINTER_UP));
        assertEquals(null, TouchEventMapper.phaseForAction(99));
    }

    private static void testScrollJson() {
        assertEquals("{\"type\":\"scroll\",\"dx\":12.500,\"dy\":-4.250}",
                LengthPrefixedProtocol.scrollJson(12.5, -4.25));
    }

    private static void testScrollGestureTrackerProducesPixelDeltas() {
        ScrollGestureTracker tracker = new ScrollGestureTracker();
        assertFalse(tracker.isActive());
        tracker.begin(100, 200, 2.0);
        assertTrue(tracker.isActive());
        ScrollGestureTracker.Delta first = tracker.move(130, 220);
        assertEquals(-15.0, first.dx);
        assertEquals(-10.0, first.dy);
        ScrollGestureTracker.Delta second = tracker.move(150, 210);
        assertEquals(-10.0, second.dx);
        assertEquals(5.0, second.dy);
        tracker.end();
        assertFalse(tracker.isActive());
        assertEquals(null, tracker.move(200, 200));
    }

    private static void testTouchGestureCoordinatorDefersTapUntilGestureIsKnown() {
        TouchGestureCoordinator touch = new TouchGestureCoordinator(0.01);
        assertEquals(0, touch.begin(0.5, 0.5).size());
        assertEquals(0, touch.move(0.505, 0.5).size());
        List<TouchGestureCoordinator.Event> tap = touch.end(0.505, 0.5);
        assertEquals(2, tap.size());
        assertEquals("began", tap.get(0).phase);
        assertEquals("ended", tap.get(1).phase);

        assertEquals(0, touch.begin(0.2, 0.2).size());
        List<TouchGestureCoordinator.Event> drag = touch.move(0.25, 0.2);
        assertEquals(2, drag.size());
        assertEquals("began", drag.get(0).phase);
        assertEquals("moved", drag.get(1).phase);
    }

    private static void testTouchGestureCoordinatorCancelsPendingTapForScroll() {
        TouchGestureCoordinator touch = new TouchGestureCoordinator(0.01);
        touch.begin(0.5, 0.5);
        assertEquals(0, touch.cancel().size());
    }

    private static void testControlMessageWriterDoesNotWriteOnCallerThread() throws Exception {
        List<Runnable> queued = new ArrayList<>();
        ControlMessageWriter writer = new ControlMessageWriter(queued::add);
        ByteArrayOutputStream out = new ByteArrayOutputStream();
        writer.send(out, "{\"type\":\"touch\"}");
        assertEquals(0, out.size());
        assertEquals(1, queued.size());
        queued.get(0).run();
        byte[] decoded = LengthPrefixedProtocol.read(new ByteArrayInputStream(out.toByteArray()));
        assertEquals("{\"type\":\"touch\"}", new String(decoded, "UTF-8"));
    }

    private static byte[] buildBaselineSps(int width, int height) {
        BitWriter bits = new BitWriter();
        bits.writeByte(0x67);
        bits.writeByte(66);
        bits.writeByte(0);
        bits.writeByte(30);
        bits.writeUE(0);
        bits.writeUE(0);
        bits.writeUE(0);
        bits.writeUE(0);
        bits.writeUE(1);
        bits.writeBit(false);
        bits.writeUE(width / 16 - 1);
        bits.writeUE(height / 16 - 1);
        bits.writeBit(true);
        bits.writeBit(true);
        bits.writeBit(false);
        bits.writeBit(false);
        bits.writeBit(true);
        return bits.toByteArray();
    }

    private static byte[] concat(byte[]... chunks) {
        int len = 0;
        for (byte[] chunk : chunks) len += chunk.length;
        byte[] out = new byte[len];
        int offset = 0;
        for (byte[] chunk : chunks) {
            System.arraycopy(chunk, 0, out, offset, chunk.length);
            offset += chunk.length;
        }
        return out;
    }

    private static void assertTrue(boolean value) {
        if (!value) throw new AssertionError("expected true");
    }

    private static void assertFalse(boolean value) {
        if (value) throw new AssertionError("expected false");
    }

    private static void assertEquals(Object expected, Object actual) {
        if (expected == null ? actual != null : !expected.equals(actual)) {
            throw new AssertionError("expected " + expected + " but got " + actual);
        }
    }

    private static void assertContains(String value, String expectedSubstring) {
        if (!value.contains(expectedSubstring)) {
            throw new AssertionError("expected " + value + " to contain " + expectedSubstring);
        }
    }

    private static final class BitWriter {
        private final List<Boolean> bits = new ArrayList<>();

        void writeByte(int value) {
            for (int i = 7; i >= 0; i--) {
                writeBit(((value >> i) & 1) == 1);
            }
        }

        void writeBit(boolean bit) {
            bits.add(bit);
        }

        void writeUE(int value) {
            int codeNum = value + 1;
            int bitsRequired = 32 - Integer.numberOfLeadingZeros(codeNum);
            for (int i = 0; i < bitsRequired - 1; i++) writeBit(false);
            for (int i = bitsRequired - 1; i >= 0; i--) {
                writeBit(((codeNum >> i) & 1) == 1);
            }
        }

        byte[] toByteArray() {
            while (bits.size() % 8 != 0) bits.add(false);
            byte[] out = new byte[bits.size() / 8];
            for (int i = 0; i < bits.size(); i++) {
                if (bits.get(i)) {
                    out[i / 8] |= (byte) (1 << (7 - (i % 8)));
                }
            }
            return out;
        }
    }
}

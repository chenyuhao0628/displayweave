package app.opendisplay.android.protocol;

import java.io.ByteArrayInputStream;
import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.Arrays;
import java.util.Properties;

final class WireContractSelfTest {
    static void run() throws Exception {
        Properties vectors = new Properties();
        Path fixture = null;
        for (String prefix : new String[]{"", "../", "../../"}) {
            Path candidate = Path.of(prefix + "tools/fixtures/wire-contract-v1.properties");
            if (Files.exists(candidate)) { fixture = candidate; break; }
        }
        if (fixture == null) throw new AssertionError("shared wire fixtures missing");
        try (var input = Files.newInputStream(fixture)) { vectors.load(input); }
        for (String name : new String[]{"ping", "legacy", "h264", "hevc", "desktop", "pencil", "action", "tcpAudio"}) {
            byte[] payload = hex(vectors, name + "Payload"), framed = hex(vectors, name + "Frame");
            equal(LengthPrefixedProtocol.encode(payload), framed);
            // A transport may return one payload byte on every read.
            ByteArrayInputStream fragmented = new ByteArrayInputStream(framed) {
                @Override public synchronized int read(byte[] b, int off, int len) { return super.read(b, off, Math.min(1, len)); }
            };
            equal(LengthPrefixedProtocol.read(fragmented), payload);
            byte[] twice = new byte[framed.length * 2];
            System.arraycopy(framed, 0, twice, 0, framed.length);
            System.arraycopy(framed, 0, twice, framed.length, framed.length);
            var joined = new ByteArrayInputStream(twice);
            equal(LengthPrefixedProtocol.read(joined), payload);
            equal(LengthPrefixedProtocol.read(joined), payload);
            for (int end = 0; end < framed.length; end++) {
                try {
                    LengthPrefixedProtocol.read(new ByteArrayInputStream(Arrays.copyOf(framed, end)));
                    throw new AssertionError("truncated frame accepted");
                } catch (IOException expected) { }
            }
        }
        for (String name : new String[]{"zero", "oversize", "negative"}) {
            try {
                LengthPrefixedProtocol.read(new ByteArrayInputStream(hex(vectors, name)), LengthPrefixedProtocol.ABSOLUTE_MAX_FRAME_BYTES);
                throw new AssertionError("invalid length accepted");
            } catch (LengthPrefixedProtocol.FrameLengthException expected) { }
        }
        for (String name : new String[]{"h264", "hevc"}) {
            byte[] wire = hex(vectors, name + "Payload");
            var parsed = BinaryFrameHeaderV2.parse(wire);
            equal(BinaryFrameHeaderV2.encode(parsed.flags, parsed.sessionEpoch, parsed.configVersion, parsed.frameSequence,
                parsed.captureTimestampMs, parsed.sendTimestampMs, Arrays.copyOfRange(wire, parsed.payloadOffset, wire.length)), wire);
            if (parsed.sessionEpoch != 8 || parsed.configVersion != 12 || parsed.frameSequence != (name.equals("h264") ? 44 : 45)) {
                throw new AssertionError("wrong DWV2 identity");
            }
        }
        for (String name : new String[]{"badVersion", "badFlags", "badIdentity", "badPayloadLength", "truncatedBinary"}) {
            try { BinaryFrameHeaderV2.parse(hex(vectors, name)); throw new AssertionError("invalid DWV2 accepted"); }
            catch (BinaryFrameHeaderV2.ParseException expected) { }
        }
        equal(AnnexB.stripTelemetryPrefix(hex(vectors, "legacyPayload")), hex(vectors, "annexB"));

        // Verify AndroidStylusInput and AndroidDesktopInput match shared golden vectors byte-for-byte.
        AndroidDesktopInput desktop = new AndroidDesktopInput();
        desktop.configureFromInputConfig(true,
                "{\"type\":\"inputConfig\",\"inputCaps\":[\"mac-input-v1\"],"
                        + "\"inputSession\":\"11111111-2222-4333-8444-555555555555\","
                        + "\"inputStatus\":\"ready\"}");
        java.util.List<String> desktopMoves = desktop.onPointerEvent(
                AndroidDesktopInput.ACTION_HOVER_MOVE,
                250.0, 750.0, 1000.0, 1000.0, 0, 0.0, 0.0, 0, 100L);
        if (desktopMoves.size() != 1) {
            throw new AssertionError("expected single desktop move message");
        }
        equal(LengthPrefixedProtocol.jsonBytes(desktopMoves.get(0)), hex(vectors, "desktopPayload"));
        equal(LengthPrefixedProtocol.encode(LengthPrefixedProtocol.jsonBytes(desktopMoves.get(0))),
                hex(vectors, "desktopFrame"));

        AndroidStylusInput.Sample pencilSample = new AndroidStylusInput.Sample(
                AndroidStylusInput.Phase.DOWN,
                0.25, 0.75, 0.5, 0.0, 1.5, 1.5,
                AndroidStylusInput.Tool.ERASER);
        equal(LengthPrefixedProtocol.jsonBytes(pencilSample.toPencilV2Json()),
                hex(vectors, "pencilPayload"));
        equal(LengthPrefixedProtocol.encode(LengthPrefixedProtocol.jsonBytes(pencilSample.toPencilV2Json())),
                hex(vectors, "pencilFrame"));

        String actionJson = AndroidStylusInput.pencilActionJson(
                "11111111-2222-4333-8444-555555555555",
                1L,
                AndroidStylusInput.RemoteAction.UNDO);
        equal(LengthPrefixedProtocol.jsonBytes(actionJson), hex(vectors, "actionPayload"));
        equal(LengthPrefixedProtocol.encode(LengthPrefixedProtocol.jsonBytes(actionJson)),
                hex(vectors, "actionFrame"));

        // Shared udpMediaV1 deterministic golden vectors (present once wire-contract-v1.properties rev 2 is merged).
        for (String key : new String[]{"udpHeaderVideoData", "udpHeaderCursor", "udpHeaderAudio"}) {
            if (vectors.getProperty(key) != null) {
                byte[] rawHeader = hex(vectors, key);
                UdpMediaProtocol.Header decoded = UdpMediaProtocol.Header.decode(rawHeader, rawHeader.length);
                equal(decoded.encode(), rawHeader);
            }
        }
        if (vectors.getProperty("udpCursorPayload") != null) {
            byte[] rawCursor = hex(vectors, "udpCursorPayload");
            UdpMediaProtocol.CursorPayload cursor = UdpMediaProtocol.CursorPayload.decode(rawCursor);
            equal(cursor.encode(), rawCursor);
        }
        if (vectors.getProperty("udpAudioPayload") != null) {
            byte[] rawAudio = hex(vectors, "udpAudioPayload");
            UdpMediaProtocol.AudioPayload audio = UdpMediaProtocol.AudioPayload.decode(rawAudio);
            equal(audio.encode(), rawAudio);
        }
        if (vectors.getProperty("udpAudioOpusPayload") != null && vectors.getProperty("tcpAudioPayload") != null) {
            byte[] rawOpus = hex(vectors, "udpAudioOpusPayload");
            UdpMediaProtocol.AudioPayload opusAudio = UdpMediaProtocol.AudioPayload.decode(rawOpus);
            equal(opusAudio.encode(), rawOpus);
            if (opusAudio.formatFlags != UdpMediaProtocol.AudioPayload.FORMAT_OPUS || opusAudio.audioSeq != 6L) {
                throw new AssertionError("wrong Opus audio golden metadata");
            }
            String tcpJson = UdpMediaProtocol.TcpAudioFrame.encodeJson(opusAudio);
            equal(LengthPrefixedProtocol.jsonBytes(tcpJson), hex(vectors, "tcpAudioPayload"));
            UdpMediaProtocol.AudioPayload decodedTcp = UdpMediaProtocol.TcpAudioFrame.decodeJson(tcpJson);
            equal(decodedTcp.encode(), rawOpus);
        }
        if (vectors.getProperty("opusHead48kStereo") != null) {
            java.nio.ByteBuffer head = java.nio.ByteBuffer.allocate(19).order(java.nio.ByteOrder.LITTLE_ENDIAN);
            head.put("OpusHead".getBytes(java.nio.charset.StandardCharsets.US_ASCII));
            head.put((byte) 1).put((byte) 2).putShort((short) 0).putInt(48_000).putShort((short) 0).put((byte) 0);
            equal(head.array(), hex(vectors, "opusHead48kStereo"));
            equal(java.nio.ByteBuffer.allocate(8).order(java.nio.ByteOrder.LITTLE_ENDIAN).putLong(0L).array(),
                    hex(vectors, "opusCsd1PreSkip"));
            equal(java.nio.ByteBuffer.allocate(8).order(java.nio.ByteOrder.LITTLE_ENDIAN).putLong(80_000_000L).array(),
                    hex(vectors, "opusCsd2SeekPreRoll"));
        }
        if (vectors.getProperty("udpRootSecret") != null && vectors.getProperty("udpS2RKeyEpoch1") != null) {
            UdpMediaProtocol.KeyMaterial km = UdpMediaProtocol.KeyMaterial.derive(
                    hex(vectors, "udpRootSecret"), 1L);
            equal(km.senderToReceiverKey, hex(vectors, "udpS2RKeyEpoch1"));
            equal(km.senderToReceiverSalt, hex(vectors, "udpS2RSaltEpoch1"));
            equal(km.receiverToSenderKey, hex(vectors, "udpR2SKeyEpoch1"));
            equal(km.receiverToSenderSalt, hex(vectors, "udpR2SSaltEpoch1"));
            equal(km.nonce(UdpMediaProtocol.DIR_SENDER_TO_RECEIVER, 1L), hex(vectors, "udpS2RNonceSeq1"));
            equal(km.nonce(UdpMediaProtocol.DIR_RECEIVER_TO_SENDER, 1L), hex(vectors, "udpR2SNonceSeq1"));

            UdpMediaProtocol.CryptoSession sender = new UdpMediaProtocol.CryptoSession(km);
            UdpMediaProtocol.CryptoSession receiver = new UdpMediaProtocol.CryptoSession(km);
            byte[] cursorDg = hex(vectors, "udpCursorSealedDatagram");
            byte[] audioDg = hex(vectors, "udpAudioSealedDatagram");
            equal(sender.seal(
                    UdpMediaProtocol.DIR_SENDER_TO_RECEIVER,
                    UdpMediaProtocol.PACKET_CURSOR,
                    0, 123_500L, 0L, 0, 1, hex(vectors, "udpCursorPayload")),
                    cursorDg);
            equal(sender.seal(
                    UdpMediaProtocol.DIR_SENDER_TO_RECEIVER,
                    UdpMediaProtocol.PACKET_AUDIO,
                    0, 123_600L, 0L, 0, 1, hex(vectors, "udpAudioPayload")),
                    audioDg);
            UdpMediaProtocol.AuthenticatedPacket openedCursor =
                    receiver.open(cursorDg, cursorDg.length, UdpMediaProtocol.DIR_SENDER_TO_RECEIVER);
            equal(openedCursor.payload, hex(vectors, "udpCursorPayload"));
            UdpMediaProtocol.AuthenticatedPacket openedAudio =
                    receiver.open(audioDg, audioDg.length, UdpMediaProtocol.DIR_SENDER_TO_RECEIVER);
            equal(openedAudio.payload, hex(vectors, "udpAudioPayload"));
        }

        System.out.println("Shared wire fixtures: Java framing/fragmentation/EOF, DWV2, input, and legacy Annex-B PASS");
    }
    private static byte[] hex(Properties fixtures, String key) {
        String text = fixtures.getProperty(key);
        byte[] bytes = new byte[text.length() / 2];
        for (int i = 0; i < bytes.length; i++) bytes[i] = (byte) Integer.parseInt(text.substring(i * 2, i * 2 + 2), 16);
        return bytes;
    }
    private static void equal(byte[] left, byte[] right) { if (!Arrays.equals(left, right)) throw new AssertionError("fixture mismatch"); }
}

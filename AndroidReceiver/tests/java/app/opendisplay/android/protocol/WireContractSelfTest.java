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
        for (String name : new String[]{"ping", "legacy", "h264", "hevc", "desktop", "pencil", "action"}) {
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
        System.out.println("Shared wire fixtures: Java framing/fragmentation/EOF, DWV2 and legacy Annex-B PASS");
    }
    private static byte[] hex(Properties fixtures, String key) {
        String text = fixtures.getProperty(key);
        byte[] bytes = new byte[text.length() / 2];
        for (int i = 0; i < bytes.length; i++) bytes[i] = (byte) Integer.parseInt(text.substring(i * 2, i * 2 + 2), 16);
        return bytes;
    }
    private static void equal(byte[] left, byte[] right) { if (!Arrays.equals(left, right)) throw new AssertionError("fixture mismatch"); }
}

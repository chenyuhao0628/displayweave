package app.opendisplay.android;

import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.nio.ByteBuffer;
import java.nio.charset.CharacterCodingException;
import java.nio.charset.CodingErrorAction;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.SecureRandom;
import java.util.Arrays;
import java.util.Base64;

/** Bounded pre-application messages carried inside authenticated platform TLS. */
public final class SecurePairingProtocol {
    private SecurePairingProtocol() { }
    public static final int MAX_AUTH_BYTES = 4096;
    public static final int MAX_INVITATION_BYTES = 2048;
    static boolean validID(String value) { return value != null && !value.isEmpty() && validName(value, 256); }
    static boolean validName(String value, int maximum) {
        if (value == null || value.length() > maximum || !StandardCharsets.UTF_8.newEncoder().canEncode(value)
                || value.getBytes(StandardCharsets.UTF_8).length > maximum) return false;
        for (int i = 0; i < value.length(); i++) if (value.charAt(i) < 32 || value.charAt(i) == 127) return false;
        return true;
    }
    static byte[] fingerprintBytes(String value) throws IOException {
        if (value == null || value.length() != 64 || !value.matches("[0-9a-f]{64}")) throw new IOException("invalid full certificate pin");
        byte[] bytes = new byte[32];
        for (int i = 0; i < 32; i++) bytes[i] = (byte) Integer.parseInt(value.substring(i * 2, i * 2 + 2), 16);
        return bytes;
    }
    static String hex(byte[] bytes) {
        StringBuilder output = new StringBuilder(bytes.length * 2);
        for (byte value : bytes) output.append(String.format(java.util.Locale.ROOT, "%02x", value & 255));
        return output.toString();
    }
    static byte[] randomToken() { byte[] token = new byte[32]; new SecureRandom().nextBytes(token); return token; }
    static boolean equalToken(byte[] left, byte[] right) {
        return left != null && right != null && left.length == 32 && right.length == 32 && MessageDigest.isEqual(left, right);
    }
    static void string(ByteArrayOutputStream output, String value) {
        byte[] bytes = value.getBytes(StandardCharsets.UTF_8);
        output.write(bytes.length >> 8); output.write(bytes.length & 255); output.write(bytes, 0, bytes.length);
    }
    static final class Reader {
        final byte[] data; int offset;
        Reader(byte[] data) { this.data = data; }
        byte[] take(int size) throws IOException {
            if (size < 0 || size > data.length - offset) throw new IOException("truncated secure message");
            byte[] result = Arrays.copyOfRange(data, offset, offset + size); offset += size; return result;
        }
        String string(int maximum) throws IOException {
            byte[] header = take(2); int size = (header[0] & 255) << 8 | (header[1] & 255);
            if (size > maximum) throw new IOException("secure string exceeds limit");
            try {
                return StandardCharsets.UTF_8.newDecoder().onMalformedInput(CodingErrorAction.REPORT)
                        .onUnmappableCharacter(CodingErrorAction.REPORT).decode(ByteBuffer.wrap(take(size))).toString();
            } catch (CharacterCodingException error) { throw new IOException("invalid secure UTF-8", error); }
        }
        boolean finished() { return offset == data.length; }
    }
    static void magic(Reader reader, String expected) throws IOException {
        if (!Arrays.equals(reader.take(4), expected.getBytes(StandardCharsets.US_ASCII))) throw new IOException("unsupported secure message");
    }

    public static final class Invitation {
        public final String receiverID, certificateSHA256;
        public final byte[] token;
        public Invitation(String receiverID, String certificateSHA256, byte[] token) {
            this.receiverID = receiverID; this.certificateSHA256 = certificateSHA256; this.token = token.clone();
        }
        public String encode() throws IOException {
            if (!validID(receiverID) || token.length != 32) throw new IOException("invalid pairing invitation");
            byte[] pin = fingerprintBytes(certificateSHA256);
            ByteArrayOutputStream output = new ByteArrayOutputStream(); output.write("DWP1".getBytes(StandardCharsets.US_ASCII));
            string(output, receiverID); output.write(pin); output.write(token);
            return "DW1." + Base64.getUrlEncoder().withoutPadding().encodeToString(output.toByteArray());
        }
        public static Invitation decode(String text) throws IOException {
            if (text == null || text.length() > MAX_INVITATION_BYTES
                    || text.getBytes(StandardCharsets.UTF_8).length > MAX_INVITATION_BYTES) throw new IOException("invitation too large");
            String value = text.trim();
            if (!value.startsWith("DW1.") || !value.substring(4).matches("[A-Za-z0-9_-]+")) throw new IOException("invalid invitation encoding");
            byte[] bytes;
            try { bytes = Base64.getUrlDecoder().decode(value.substring(4)); }
            catch (IllegalArgumentException error) { throw new IOException("invalid invitation encoding", error); }
            Reader reader = new Reader(bytes); magic(reader, "DWP1");
            String id = reader.string(256), pin = hex(reader.take(32)); byte[] token = reader.take(32);
            if (!reader.finished() || !validID(id)) throw new IOException("invalid invitation fields");
            Invitation result = new Invitation(id, pin, token);
            if (!result.encode().equals(value)) throw new IOException("noncanonical invitation encoding");
            return result;
        }
    }

    public static final class Auth {
        public final String installID, name;
        public final byte[] token;
        public Auth(String installID, String name, byte[] token) {
            this.installID = installID; this.name = name; this.token = token == null ? null : token.clone();
        }
        public byte[] encode() throws IOException {
            if (!validID(installID) || !validName(name, 128) || (token != null && token.length != 32)) throw new IOException("invalid auth fields");
            ByteArrayOutputStream output = new ByteArrayOutputStream(); output.write("DWA1".getBytes(StandardCharsets.US_ASCII));
            output.write(token == null ? 0 : 1); string(output, installID); string(output, name);
            if (token != null) output.write(token);
            return output.toByteArray();
        }
        public static Auth decode(byte[] data) throws IOException {
            if (data == null || data.length > MAX_AUTH_BYTES) throw new IOException("auth message too large");
            Reader reader = new Reader(data); magic(reader, "DWA1"); int flags = reader.take(1)[0] & 255;
            if (flags > 1) throw new IOException("invalid auth flags");
            String id = reader.string(256), name = reader.string(128); byte[] token = flags == 1 ? reader.take(32) : null;
            if (!reader.finished() || !validID(id) || !validName(name, 128)) throw new IOException("invalid auth fields");
            return new Auth(id, name, token);
        }
    }

    public static byte[] ready(String receiverID) throws IOException {
        if (!validID(receiverID)) throw new IOException("invalid receiver identity");
        ByteArrayOutputStream output = new ByteArrayOutputStream(); output.write("DWR1".getBytes(StandardCharsets.US_ASCII));
        string(output, receiverID); return output.toByteArray();
    }
    public static String readyIdentity(byte[] data) throws IOException {
        if (data == null || data.length > MAX_AUTH_BYTES) throw new IOException("ready message too large");
        Reader reader = new Reader(data); magic(reader, "DWR1"); String id = reader.string(256);
        if (!reader.finished() || !validID(id)) throw new IOException("invalid ready identity");
        return id;
    }
}

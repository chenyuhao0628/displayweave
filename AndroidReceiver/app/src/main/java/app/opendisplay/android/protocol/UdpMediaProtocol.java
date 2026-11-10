package app.opendisplay.android.protocol;

import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.nio.charset.StandardCharsets;
import java.security.GeneralSecurityException;
import java.security.SecureRandom;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Base64;
import java.util.Collections;
import java.util.HashMap;
import java.util.Iterator;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.TreeMap;
import java.util.regex.Matcher;
import java.util.regex.Pattern;
import javax.crypto.Cipher;
import javax.crypto.Mac;
import javax.crypto.spec.GCMParameterSpec;
import javax.crypto.spec.SecretKeySpec;

/**
 * Wire protocol, RFC 5869 HKDF-SHA256 key derivation, per-packet AES-128-GCM
 * authentication with 64-bit rollover counter (ROC), 1024-packet anti-replay window,
 * GF(256) Cauchy/XOR frame-level FEC, bounded 4-frame reassembler, NACK generator,
 * monotonic jitter buffer, and 5ms burst arrival-gradient feedback for {@code udpMediaV1}.
 */
public final class UdpMediaProtocol {
    public static final int CURRENT_VERSION = 1;
    public static final int HEADER_BYTES = 16;
    public static final int GCM_TAG_BYTES = 16;
    public static final int MAX_PAYLOAD_BYTES = 1200;
    public static final int MAX_DATAGRAM_BYTES = HEADER_BYTES + MAX_PAYLOAD_BYTES + GCM_TAG_BYTES;
    public static final int MAX_FRAGMENTS_PER_FRAME = 2048;
    public static final int ROOT_SECRET_BYTES = 32;
    public static final int FRAME_METADATA_PREFIX_BYTES = 16;
    public static final int MAX_FRAME_BYTES = 4 * 1024 * 1024;

    public static final int PACKET_VIDEO_DATA = 0;
    public static final int PACKET_VIDEO_PARITY = 1;
    public static final int PACKET_NACK = 2;
    public static final int PACKET_FEEDBACK = 3;
    public static final int PACKET_PROBE = 4;

    public static final int FLAG_KEYFRAME = 1 << 0;
    public static final int FLAG_END_OF_FRAME = 1 << 1;
    public static final int FLAG_RETRANSMIT = 1 << 2;
    public static final int FLAG_PROBE_ACK = 1 << 2;

    public static final int DIR_SENDER_TO_RECEIVER = 0;
    public static final int DIR_RECEIVER_TO_SENDER = 1;

    private static final byte[] HKDF_SALT =
            "DisplayWeave-UDPMediaV1-Salt-2026".getBytes(StandardCharsets.UTF_8);

    private UdpMediaProtocol() {}

    public static int makeEpochTag(long sessionEpoch) {
        return (int) (sessionEpoch & 0xFFL);
    }

    /** Compact 16-byte wire header authenticated as AAD in AES-128-GCM. */
    public static final class Header {
        public final int version;
        public final int packetType;
        public final int flags;
        public final int epochTag;
        public final int packetSeq;
        public final long sendTimeUs;
        public final long frameId;
        public final int fragIndex;
        public final int fragCount;

        public Header(
                int version,
                int packetType,
                int flags,
                int epochTag,
                int packetSeq,
                long sendTimeUs,
                long frameId,
                int fragIndex,
                int fragCount) {
            this.version = version & 0x03;
            this.packetType = packetType & 0x07;
            this.flags = flags & 0x07;
            this.epochTag = epochTag & 0xFF;
            this.packetSeq = packetSeq & 0xFFFF;
            this.sendTimeUs = sendTimeUs & 0xFFFF_FFFFL;
            this.frameId = frameId & 0xFFFF_FFFFL;
            this.fragIndex = fragIndex & 0xFFFF;
            this.fragCount = fragCount & 0xFFFF;
        }

        public byte[] encode() {
            byte[] out = new byte[HEADER_BYTES];
            out[0] = (byte) (((version & 0x03) << 6)
                    | ((packetType & 0x07) << 3)
                    | (flags & 0x07));
            out[1] = (byte) (epochTag & 0xFF);
            writeUInt16(out, 2, packetSeq);
            writeUInt32(out, 4, sendTimeUs);
            writeUInt32(out, 8, frameId);
            writeUInt16(out, 12, fragIndex);
            writeUInt16(out, 14, fragCount);
            return out;
        }

        public static Header decode(byte[] data, int length) {
            if (data == null || length < HEADER_BYTES || length > data.length) {
                throw new IllegalArgumentException("UDP packet shorter than 16-byte header");
            }
            int byte0 = Byte.toUnsignedInt(data[0]);
            int version = (byte0 >> 6) & 0x03;
            if (version != CURRENT_VERSION) {
                throw new IllegalArgumentException("unsupported UDP version: " + version);
            }
            int packetType = (byte0 >> 3) & 0x07;
            if (packetType < PACKET_VIDEO_DATA || packetType > PACKET_PROBE) {
                throw new IllegalArgumentException("invalid UDP packetType: " + packetType);
            }
            int flags = byte0 & 0x07;
            int epochTag = Byte.toUnsignedInt(data[1]);
            int packetSeq = readUInt16(data, 2);
            long sendTimeUs = readUInt32(data, 4);
            long frameId = readUInt32(data, 8);
            int fragIndex = readUInt16(data, 12);
            int fragCount = readUInt16(data, 14);
            if (packetType == PACKET_VIDEO_DATA) {
                if (fragCount < 1 || fragCount > MAX_FRAGMENTS_PER_FRAME || fragIndex >= fragCount) {
                    throw new IllegalArgumentException("invalid UDP video fragment bounds");
                }
            }
            return new Header(
                    version, packetType, flags, epochTag,
                    packetSeq, sendTimeUs, frameId, fragIndex, fragCount);
        }
    }

    /** 1024-packet sliding anti-replay window with 64-bit rollover counter (ROC). */
    public static final class AntiReplayWindow {
        public static final long WINDOW_SIZE = 1024L;
        private static final int WORD_COUNT = 16;

        private long highestAuthenticatedSeq = 0;
        private boolean hasAuthenticatedAny = false;
        private final long[] words = new long[WORD_COUNT];

        public long highestAuthenticatedSeq() {
            return highestAuthenticatedSeq;
        }

        public boolean hasAuthenticatedAny() {
            return hasAuthenticatedAny;
        }

        public long estimateExtendedSequence(int packetSeq16) {
            long seq16 = packetSeq16 & 0xFFFFL;
            if (!hasAuthenticatedAny) {
                return seq16;
            }
            long highestLow16 = highestAuthenticatedSeq & 0xFFFFL;
            long baseEpoch = highestAuthenticatedSeq & ~0xFFFFL;
            long delta = seq16 - highestLow16;
            if (delta >= -32768L && delta <= 32767L) {
                return highestAuthenticatedSeq + delta;
            } else if (delta < -32768L) {
                return baseEpoch + 0x10000L + seq16;
            } else {
                return baseEpoch >= 0x10000L ? (baseEpoch - 0x10000L + seq16) : seq16;
            }
        }

        public boolean canAccept(long extendedSeq) {
            if (extendedSeq < 0) {
                return false;
            }
            if (!hasAuthenticatedAny) {
                return true;
            }
            if (extendedSeq > highestAuthenticatedSeq) {
                return true;
            }
            long age = highestAuthenticatedSeq - extendedSeq;
            if (age >= WINDOW_SIZE) {
                return false;
            }
            int wordIndex = (int) (age >>> 6);
            long bitMask = 1L << (age & 63L);
            return (words[wordIndex] & bitMask) == 0L;
        }

        public void recordAuthenticated(long extendedSeq) {
            if (extendedSeq < 0) {
                return;
            }
            if (!hasAuthenticatedAny) {
                hasAuthenticatedAny = true;
                highestAuthenticatedSeq = extendedSeq;
                words[0] = 1L;
                return;
            }
            if (extendedSeq > highestAuthenticatedSeq) {
                long shift = extendedSeq - highestAuthenticatedSeq;
                shiftWindow(shift);
                highestAuthenticatedSeq = extendedSeq;
                words[0] |= 1L;
                return;
            }
            long age = highestAuthenticatedSeq - extendedSeq;
            if (age >= WINDOW_SIZE) {
                return;
            }
            int wordIndex = (int) (age >>> 6);
            long bitMask = 1L << (age & 63L);
            words[wordIndex] |= bitMask;
        }

        private void shiftWindow(long shift) {
            if (shift <= 0) {
                return;
            }
            if (shift >= WINDOW_SIZE) {
                Arrays.fill(words, 0L);
                return;
            }
            int wordShift = (int) (shift >>> 6);
            int bitShift = (int) (shift & 63L);
            if (wordShift > 0) {
                for (int i = WORD_COUNT - 1; i >= wordShift; i--) {
                    words[i] = words[i - wordShift];
                }
                for (int i = 0; i < wordShift; i++) {
                    words[i] = 0L;
                }
            }
            if (bitShift > 0) {
                for (int i = WORD_COUNT - 1; i >= 1; i--) {
                    words[i] = (words[i] << bitShift) | (words[i - 1] >>> (64 - bitShift));
                }
                words[0] <<= bitShift;
            }
        }
    }

    /** RFC 5869 HKDF-SHA256 session keys and salts matching {@code UDPMediaKeyMaterial}. */
    public static final class KeyMaterial {
        public final long sessionEpoch;
        public final byte[] senderToReceiverKey;
        public final byte[] senderToReceiverSalt;
        public final byte[] receiverToSenderKey;
        public final byte[] receiverToSenderSalt;

        private KeyMaterial(
                long sessionEpoch,
                byte[] senderToReceiverKey,
                byte[] senderToReceiverSalt,
                byte[] receiverToSenderKey,
                byte[] receiverToSenderSalt) {
            this.sessionEpoch = sessionEpoch;
            this.senderToReceiverKey = senderToReceiverKey;
            this.senderToReceiverSalt = senderToReceiverSalt;
            this.receiverToSenderKey = receiverToSenderKey;
            this.receiverToSenderSalt = receiverToSenderSalt;
        }

        public static byte[] generateRootSecret() {
            byte[] secret = new byte[ROOT_SECRET_BYTES];
            new SecureRandom().nextBytes(secret);
            return secret;
        }

        public static KeyMaterial derive(byte[] rootSecret, long sessionEpoch) {
            if (rootSecret == null || rootSecret.length != ROOT_SECRET_BYTES || sessionEpoch <= 0) {
                throw new IllegalArgumentException("invalid UDP root secret or sessionEpoch");
            }
            byte[] prk = hmacSha256(HKDF_SALT, rootSecret);
            byte[] s2rInfo = ("displayweave-udp-v1|s2r|" + sessionEpoch)
                    .getBytes(StandardCharsets.UTF_8);
            byte[] r2sInfo = ("displayweave-udp-v1|r2s|" + sessionEpoch)
                    .getBytes(StandardCharsets.UTF_8);
            byte[] s2rOkm = hkdfExpand(prk, s2rInfo, 28);
            byte[] r2sOkm = hkdfExpand(prk, r2sInfo, 28);
            return new KeyMaterial(
                    sessionEpoch,
                    Arrays.copyOfRange(s2rOkm, 0, 16),
                    Arrays.copyOfRange(s2rOkm, 16, 28),
                    Arrays.copyOfRange(r2sOkm, 0, 16),
                    Arrays.copyOfRange(r2sOkm, 16, 28));
        }

        public byte[] nonce(int direction, long extendedSequence) {
            byte[] baseSalt = direction == DIR_SENDER_TO_RECEIVER
                    ? senderToReceiverSalt
                    : receiverToSenderSalt;
            byte[] out = Arrays.copyOf(baseSalt, 12);
            long directionalSeq = (((long) (direction & 0x01)) << 63)
                    | (extendedSequence & 0x7FFF_FFFF_FFFF_FFFFL);
            for (int i = 0; i < 8; i++) {
                int shift = (7 - i) * 8;
                out[4 + i] ^= (byte) ((directionalSeq >>> shift) & 0xFFL);
            }
            return out;
        }

        private static byte[] hmacSha256(byte[] key, byte[] data) {
            try {
                Mac mac = Mac.getInstance("HmacSHA256");
                mac.init(new SecretKeySpec(key, "HmacSHA256"));
                return mac.doFinal(data);
            } catch (GeneralSecurityException error) {
                throw new IllegalStateException("HmacSHA256 unavailable", error);
            }
        }

        private static byte[] hkdfExpand(byte[] prk, byte[] info, int length) {
            byte[] result = new byte[length];
            byte[] previous = new byte[0];
            int offset = 0;
            int counter = 1;
            while (offset < length) {
                byte[] input = new byte[previous.length + info.length + 1];
                System.arraycopy(previous, 0, input, 0, previous.length);
                System.arraycopy(info, 0, input, previous.length, info.length);
                input[input.length - 1] = (byte) (counter & 0xFF);
                previous = hmacSha256(prk, input);
                int copyLen = Math.min(previous.length, length - offset);
                System.arraycopy(previous, 0, result, offset, copyLen);
                offset += copyLen;
                counter++;
            }
            return result;
        }
    }

    public static final class AuthenticatedPacket {
        public final Header header;
        public final long extendedSequence;
        public final byte[] payload;

        public AuthenticatedPacket(Header header, long extendedSequence, byte[] payload) {
            this.header = header;
            this.extendedSequence = extendedSequence;
            this.payload = payload;
        }
    }

    /** Stateful per-session AES-128-GCM sealer/opener with anti-replay enforcement. */
    public static final class CryptoSession {
        public final KeyMaterial keyMaterial;
        public final int epochTag;
        private final SecretKeySpec s2rKeySpec;
        private final SecretKeySpec r2sKeySpec;
        private long nextOutgoingSequence = 1L;
        private final AntiReplayWindow replayWindow = new AntiReplayWindow();

        public CryptoSession(KeyMaterial keyMaterial) {
            this.keyMaterial = keyMaterial;
            this.epochTag = makeEpochTag(keyMaterial.sessionEpoch);
            this.s2rKeySpec = new SecretKeySpec(keyMaterial.senderToReceiverKey, "AES");
            this.r2sKeySpec = new SecretKeySpec(keyMaterial.receiverToSenderKey, "AES");
        }

        public AntiReplayWindow replayWindow() {
            return replayWindow;
        }

        public void setNextOutgoingSequenceForTesting(long nextSeq) {
            this.nextOutgoingSequence = nextSeq;
        }

        public byte[] seal(
                int direction,
                int packetType,
                int flags,
                long sendTimeUs,
                long frameId,
                int fragIndex,
                int fragCount,
                byte[] payload) throws GeneralSecurityException {
            byte[] safePayload = payload == null ? new byte[0] : payload;
            if (safePayload.length > MAX_PAYLOAD_BYTES) {
                throw new IllegalArgumentException("UDP payload exceeds maxPayloadBytes");
            }
            long extendedSeq = nextOutgoingSequence++;
            Header header = new Header(
                    CURRENT_VERSION,
                    packetType,
                    flags,
                    epochTag,
                    (int) (extendedSeq & 0xFFFFL),
                    sendTimeUs,
                    frameId,
                    fragIndex,
                    fragCount);
            byte[] headerBytes = header.encode();
            byte[] nonce = keyMaterial.nonce(direction, extendedSeq);
            SecretKeySpec keySpec = direction == DIR_SENDER_TO_RECEIVER ? s2rKeySpec : r2sKeySpec;
            Cipher cipher = Cipher.getInstance("AES/GCM/NoPadding");
            cipher.init(Cipher.ENCRYPT_MODE, keySpec, new GCMParameterSpec(128, nonce));
            cipher.updateAAD(headerBytes);
            byte[] ciphertextAndTag = cipher.doFinal(safePayload);
            byte[] datagram = new byte[headerBytes.length + ciphertextAndTag.length];
            System.arraycopy(headerBytes, 0, datagram, 0, headerBytes.length);
            System.arraycopy(ciphertextAndTag, 0, datagram, headerBytes.length, ciphertextAndTag.length);
            return datagram;
        }

        public AuthenticatedPacket open(byte[] datagram, int length, int expectedDirection)
                throws GeneralSecurityException {
            int minLength = HEADER_BYTES + GCM_TAG_BYTES;
            if (datagram == null || length < minLength || length > datagram.length
                    || length > MAX_DATAGRAM_BYTES) {
                throw new GeneralSecurityException("UDP datagram bounds invalid");
            }
            Header header = Header.decode(datagram, length);
            if (header.epochTag != epochTag) {
                throw new GeneralSecurityException("UDP epochTag mismatch");
            }
            long candidateSeq = replayWindow.estimateExtendedSequence(header.packetSeq);
            if (!replayWindow.canAccept(candidateSeq)) {
                throw new GeneralSecurityException("UDP replay rejected");
            }
            byte[] nonce = keyMaterial.nonce(expectedDirection, candidateSeq);
            SecretKeySpec keySpec =
                    expectedDirection == DIR_SENDER_TO_RECEIVER ? s2rKeySpec : r2sKeySpec;
            Cipher cipher = Cipher.getInstance("AES/GCM/NoPadding");
            cipher.init(Cipher.DECRYPT_MODE, keySpec, new GCMParameterSpec(128, nonce));
            cipher.updateAAD(datagram, 0, HEADER_BYTES);
            byte[] plaintext = cipher.doFinal(datagram, HEADER_BYTES, length - HEADER_BYTES);
            replayWindow.recordAuthenticated(candidateSeq);
            return new AuthenticatedPacket(header, candidateSeq, plaintext);
        }
    }

    /** 20-byte NACK payload matching {@code UDPMediaNackPayload}. */
    public static final class NackPayload {
        public static final int BYTE_LENGTH = 20;

        public final long frameId;
        public final int baseFragIndex;
        public final int missingCount;
        public final long missingBitmap;
        public final long rttEstimateUs;

        public NackPayload(
                long frameId,
                int baseFragIndex,
                int missingCount,
                long missingBitmap,
                long rttEstimateUs) {
            this.frameId = frameId & 0xFFFF_FFFFL;
            this.baseFragIndex = baseFragIndex & 0xFFFF;
            this.missingCount = missingCount & 0xFFFF;
            this.missingBitmap = missingBitmap;
            this.rttEstimateUs = rttEstimateUs & 0xFFFF_FFFFL;
        }

        public byte[] encode() {
            byte[] out = new byte[BYTE_LENGTH];
            writeUInt32(out, 0, frameId);
            writeUInt16(out, 4, baseFragIndex);
            writeUInt16(out, 6, missingCount);
            writeInt64(out, 8, missingBitmap);
            writeUInt32(out, 16, rttEstimateUs);
            return out;
        }

        public static NackPayload decode(byte[] data) {
            if (data == null || data.length < BYTE_LENGTH) {
                throw new IllegalArgumentException("short NACK payload");
            }
            return new NackPayload(
                    readUInt32(data, 0),
                    readUInt16(data, 4),
                    readUInt16(data, 6),
                    readInt64(data, 8),
                    readUInt32(data, 16));
        }
    }

    /** 28-byte feedback payload matching {@code UDPMediaFeedbackPayload}. */
    public static final class FeedbackPayload {
        public static final int BYTE_LENGTH = 28;

        public final long highestSeq;
        public final long receivedCount;
        public final long lostCount;
        public final int arrivalGradientUs;
        public final int decodeQueueMs;
        public final int renderFps;
        public final long echoSendTimeUs;

        public FeedbackPayload(
                long highestSeq,
                long receivedCount,
                long lostCount,
                int arrivalGradientUs,
                int decodeQueueMs,
                int renderFps,
                long echoSendTimeUs) {
            this.highestSeq = highestSeq;
            this.receivedCount = receivedCount & 0xFFFF_FFFFL;
            this.lostCount = lostCount & 0xFFFF_FFFFL;
            this.arrivalGradientUs = arrivalGradientUs;
            this.decodeQueueMs = decodeQueueMs & 0xFFFF;
            this.renderFps = renderFps & 0xFFFF;
            this.echoSendTimeUs = echoSendTimeUs & 0xFFFF_FFFFL;
        }

        public byte[] encode() {
            byte[] out = new byte[BYTE_LENGTH];
            writeInt64(out, 0, highestSeq);
            writeUInt32(out, 8, receivedCount);
            writeUInt32(out, 12, lostCount);
            writeUInt32(out, 16, Integer.toUnsignedLong(arrivalGradientUs));
            writeUInt16(out, 20, decodeQueueMs);
            writeUInt16(out, 22, renderFps);
            writeUInt32(out, 24, echoSendTimeUs);
            return out;
        }

        public static FeedbackPayload decode(byte[] data) {
            if (data == null || data.length < BYTE_LENGTH) {
                throw new IllegalArgumentException("short Feedback payload");
            }
            return new FeedbackPayload(
                    readInt64(data, 0),
                    readUInt32(data, 8),
                    readUInt32(data, 12),
                    (int) readUInt32(data, 16),
                    readUInt16(data, 20),
                    readUInt16(data, 22),
                    readUInt32(data, 24));
        }
    }

    /** Control message parsed from {@code udpMediaConfig} and reply {@code udpMediaReady}. */
    public static final class ConfigMessage {
        private static final Pattern VERSION_PATTERN =
                Pattern.compile("\"version\"\\s*:\\s*(-?\\d+)");
        private static final Pattern EPOCH_PATTERN =
                Pattern.compile("\"sessionEpoch\"\\s*:\\s*(-?\\d+)");
        private static final Pattern PORT_PATTERN =
                Pattern.compile("\"udpPort\"\\s*:\\s*(-?\\d+)");
        private static final Pattern MAX_PAYLOAD_PATTERN =
                Pattern.compile("\"maxPayloadBytes\"\\s*:\\s*(-?\\d+)");
        private static final Pattern SECRET_PATTERN =
                Pattern.compile("\"rootSecret\"\\s*:\\s*\"([^\"]+)\"");

        public final long sessionEpoch;
        public final int udpPort;
        public final byte[] rootSecret;
        public final int maxPayloadBytes;

        public ConfigMessage(long sessionEpoch, int udpPort, byte[] rootSecret, int maxPayloadBytes) {
            this.sessionEpoch = sessionEpoch;
            this.udpPort = udpPort;
            this.rootSecret = rootSecret;
            this.maxPayloadBytes = maxPayloadBytes;
        }

        public static ConfigMessage parseJson(String json) {
            if (json == null || !json.contains("\"udpMediaConfig\"")) {
                return null;
            }
            long version = matchLong(VERSION_PATTERN, json, -1);
            long epoch = matchLong(EPOCH_PATTERN, json, -1);
            long port = matchLong(PORT_PATTERN, json, -1);
            long maxPayload = matchLong(MAX_PAYLOAD_PATTERN, json, MAX_PAYLOAD_BYTES);
            Matcher secretMatcher = SECRET_PATTERN.matcher(json);
            if (version != CURRENT_VERSION || epoch <= 0 || port < 1 || port > 65535
                    || !secretMatcher.find()) {
                return null;
            }
            byte[] secret;
            try {
                secret = Base64.getDecoder().decode(secretMatcher.group(1));
            } catch (IllegalArgumentException error) {
                return null;
            }
            if (secret.length != ROOT_SECRET_BYTES) {
                return null;
            }
            int clampedPayload = (int) Math.max(512L, Math.min(maxPayload, MAX_PAYLOAD_BYTES));
            return new ConfigMessage(epoch, (int) port, secret, clampedPayload);
        }

        public static String readyJson(long sessionEpoch, int localUdpPort) {
            return String.format(
                    Locale.US,
                    "{\"type\":\"udpMediaReady\",\"version\":%d,\"sessionEpoch\":%d,\"udpPort\":%d}",
                    CURRENT_VERSION,
                    sessionEpoch,
                    localUdpPort);
        }

        private static long matchLong(Pattern pattern, String text, long fallback) {
            Matcher matcher = pattern.matcher(text);
            if (!matcher.find()) {
                return fallback;
            }
            try {
                return Long.parseLong(matcher.group(1));
            } catch (NumberFormatException error) {
                return fallback;
            }
        }
    }

    /** Galois Field GF(2^8) with polynomial 0x11d and Cauchy/XOR Reed-Solomon FEC. */
    public static final class GF256 {
        public static final int MAX_BLOCKS_PER_FRAME = 16;
        public static final int MAX_DATA_SHARDS_PER_BLOCK = 64;
        public static final int MAX_PARITY_SHARDS_PER_BLOCK = 15;

        private static final int[] EXP = new int[512];
        private static final int[] LOG = new int[256];

        static {
            int x = 1;
            for (int i = 0; i < 255; i++) {
                EXP[i] = x;
                EXP[i + 255] = x;
                LOG[x] = i;
                x <<= 1;
                if ((x & 0x100) != 0) {
                    x ^= 0x11d;
                }
            }
            EXP[510] = EXP[0];
            EXP[511] = EXP[1];
        }

        public static int mul(int a, int b) {
            int ua = a & 0xFF;
            int ub = b & 0xFF;
            if (ua == 0 || ub == 0) {
                return 0;
            }
            return EXP[LOG[ua] + LOG[ub]];
        }

        public static int inv(int a) {
            int ua = a & 0xFF;
            if (ua == 0) {
                throw new IllegalArgumentException("GF(256) division by zero");
            }
            return EXP[255 - LOG[ua]];
        }

        public static int coefficient(int parityRow, int dataCol) {
            if (parityRow == 0) {
                return 1;
            }
            return inv((parityRow & 0xFF) ^ ((16 + dataCol) & 0xFF));
        }

        public static void addScaled(byte[] destination, byte[] source, int coeff) {
            int uCoeff = coeff & 0xFF;
            if (uCoeff == 0 || source == null) {
                return;
            }
            int limit = Math.min(destination.length, source.length);
            if (uCoeff == 1) {
                for (int i = 0; i < limit; i++) {
                    destination[i] ^= source[i];
                }
            } else {
                int logCoeff = LOG[uCoeff];
                for (int i = 0; i < limit; i++) {
                    int b = Byte.toUnsignedInt(source[i]);
                    if (b != 0) {
                        destination[i] ^= (byte) EXP[logCoeff + LOG[b]];
                    }
                }
            }
        }
    }

    /** Unpacked parity descriptor carried in {@code (fragIndex, fragCount)} of {@code PACKET_VIDEO_PARITY}. */
    public static final class ParityDescriptor {
        public final int blockIndex;
        public final int blockDataCount;
        public final int parityIndexInBlock;
        public final int blockParityCount;
        public final int lastDataShardLength;

        public ParityDescriptor(
                int blockIndex,
                int blockDataCount,
                int parityIndexInBlock,
                int blockParityCount,
                int lastDataShardLength) {
            this.blockIndex = blockIndex;
            this.blockDataCount = blockDataCount;
            this.parityIndexInBlock = parityIndexInBlock;
            this.blockParityCount = blockParityCount;
            this.lastDataShardLength = lastDataShardLength;
        }

        public int encodedFragIndex() {
            return ((blockIndex & 0x0F) << 12)
                    | ((blockDataCount & 0xFF) << 4)
                    | (parityIndexInBlock & 0x0F);
        }

        public int encodedFragCount() {
            return ((lastDataShardLength & 0x0FFF) << 4)
                    | (blockParityCount & 0x0F);
        }

        public static ParityDescriptor decode(int fragIndex, int fragCount) {
            int blockIdx = (fragIndex >>> 12) & 0x0F;
            int dataCount = (fragIndex >>> 4) & 0xFF;
            int parityIdx = fragIndex & 0x0F;
            int lastLen = (fragCount >>> 4) & 0x0FFF;
            int parityCount = fragCount & 0x0F;
            if (dataCount < 1
                    || dataCount > GF256.MAX_DATA_SHARDS_PER_BLOCK
                    || parityCount < 1
                    || parityCount > GF256.MAX_PARITY_SHARDS_PER_BLOCK
                    || parityIdx >= parityCount
                    || lastLen < 1
                    || lastLen > MAX_PAYLOAD_BYTES) {
                return null;
            }
            return new ParityDescriptor(blockIdx, dataCount, parityIdx, parityCount, lastLen);
        }
    }

    /** Cauchy/XOR FEC block encoder & Gaussian-elimination decoder matching {@code UDPMediaFECEncoder}. */
    public static final class FecCoder {
        public static Map<Integer, byte[]> recoverBlockDataShards(
                int blockDataCount,
                int lastDataShardLength,
                int shardStrideLength,
                Map<Integer, byte[]> presentDataShards,
                Map<Integer, byte[]> presentParityShards) {
            List<Integer> missingCols = new ArrayList<>();
            for (int col = 0; col < blockDataCount; col++) {
                if (!presentDataShards.containsKey(col)) {
                    missingCols.add(col);
                }
            }
            if (missingCols.isEmpty()) {
                return Collections.emptyMap();
            }
            int m = missingCols.size();
            if (presentParityShards.size() < m) {
                return null;
            }
            List<Integer> sortedParityRows = new ArrayList<>(presentParityShards.keySet());
            Collections.sort(sortedParityRows);

            int[][] matrix = new int[m][m];
            byte[][] rhs = new byte[m][shardStrideLength];

            for (int eqIdx = 0; eqIdx < m; eqIdx++) {
                int pRow = sortedParityRows.get(eqIdx);
                byte[] parityData = presentParityShards.get(pRow);
                if (parityData == null || parityData.length != shardStrideLength) {
                    return null;
                }
                System.arraycopy(parityData, 0, rhs[eqIdx], 0, shardStrideLength);
                for (int col = 0; col < blockDataCount; col++) {
                    byte[] knownData = presentDataShards.get(col);
                    if (knownData != null) {
                        int coeff = GF256.coefficient(pRow, col);
                        GF256.addScaled(rhs[eqIdx], knownData, coeff);
                    }
                }
                for (int varIdx = 0; varIdx < m; varIdx++) {
                    int missingCol = missingCols.get(varIdx);
                    matrix[eqIdx][varIdx] = GF256.coefficient(pRow, missingCol);
                }
            }

            // Gaussian elimination over GF(256)
            for (int pivot = 0; pivot < m; pivot++) {
                int pivotRow = pivot;
                while (pivotRow < m && matrix[pivotRow][pivot] == 0) {
                    pivotRow++;
                }
                if (pivotRow == m) {
                    return null;
                }
                if (pivotRow != pivot) {
                    int[] tmpRow = matrix[pivot];
                    matrix[pivot] = matrix[pivotRow];
                    matrix[pivotRow] = tmpRow;

                    byte[] tmpRhs = rhs[pivot];
                    rhs[pivot] = rhs[pivotRow];
                    rhs[pivotRow] = tmpRhs;
                }

                int invPivot = GF256.inv(matrix[pivot][pivot]);
                if (invPivot != 1) {
                    for (int col = pivot; col < m; col++) {
                        matrix[pivot][col] = GF256.mul(matrix[pivot][col], invPivot);
                    }
                    byte[] scaled = new byte[shardStrideLength];
                    GF256.addScaled(scaled, rhs[pivot], invPivot);
                    rhs[pivot] = scaled;
                }

                for (int row = 0; row < m; row++) {
                    if (row == pivot) {
                        continue;
                    }
                    int factor = matrix[row][pivot];
                    if (factor == 0) {
                        continue;
                    }
                    for (int col = pivot; col < m; col++) {
                        matrix[row][col] ^= GF256.mul(factor, matrix[pivot][col]);
                    }
                    GF256.addScaled(rhs[row], rhs[pivot], factor);
                }
            }

            Map<Integer, byte[]> recovered = new HashMap<>();
            for (int varIdx = 0; varIdx < m; varIdx++) {
                int col = missingCols.get(varIdx);
                int targetLen = (col == blockDataCount - 1) ? lastDataShardLength : shardStrideLength;
                if (targetLen < 1 || targetLen > rhs[varIdx].length) {
                    return null;
                }
                recovered.put(col, Arrays.copyOf(rhs[varIdx], targetLen));
            }
            return recovered;
        }
    }

    /** Reassembled frame envelope matching {@code UDPMediaFrameEnvelope}. */
    public static final class FrameEnvelope {
        public final long frameId;
        public final boolean isKeyframe;
        public final long captureTimestampMs;
        public final long sendTimestampUs;
        public final long configVersion;
        public final byte[] annexB;
        public final long firstArrivalMonoNs;
        public final boolean recoveredByFec;

        public FrameEnvelope(
                long frameId,
                boolean isKeyframe,
                long captureTimestampMs,
                long sendTimestampUs,
                long configVersion,
                byte[] annexB,
                long firstArrivalMonoNs,
                boolean recoveredByFec) {
            this.frameId = frameId;
            this.isKeyframe = isKeyframe;
            this.captureTimestampMs = captureTimestampMs;
            this.sendTimestampUs = sendTimestampUs;
            this.configVersion = configVersion;
            this.annexB = annexB;
            this.firstArrivalMonoNs = firstArrivalMonoNs;
            this.recoveredByFec = recoveredByFec;
        }
    }

    public static List<byte[]> makeDataFragments(
            byte[] annexB, long captureTimestampMs, long configVersion, int maxPayloadBytes) {
        if (annexB == null || annexB.length == 0 || annexB.length > MAX_FRAME_BYTES) {
            throw new IllegalArgumentException("invalid annexB length");
        }
        int chunkLimit = Math.max(256, Math.min(maxPayloadBytes, MAX_PAYLOAD_BYTES));
        byte[] envelope = new byte[FRAME_METADATA_PREFIX_BYTES + annexB.length];
        writeInt64(envelope, 0, captureTimestampMs);
        writeInt64(envelope, 8, configVersion);
        System.arraycopy(annexB, 0, envelope, FRAME_METADATA_PREFIX_BYTES, annexB.length);

        List<byte[]> shards = new ArrayList<>();
        int offset = 0;
        while (offset < envelope.length) {
            int end = Math.min(offset + chunkLimit, envelope.length);
            shards.add(Arrays.copyOfRange(envelope, offset, end));
            offset = end;
        }
        return shards;
    }

    /** Bounded 4-frame reassembler with immediate data-complete submission and FEC recovery. */
    public static final class Reassembler {
        public static final int MAX_CONCURRENT_FRAMES = 4;
        public static final long REASSEMBLY_TIMEOUT_NS = 25_000_000L;
        public static final long NACK_REORDER_DELAY_NS = 2_000_000L;
        public static final long NACK_COOLDOWN_NS = 8_000_000L;
        public static final long MAX_RTT_FOR_NACK_US = 80_000L;

        private static final class FrameAssembly {
            final long frameId;
            boolean isKeyframe;
            long sendTimestampUs;
            int expectedDataCount;
            final long firstArrivalMonoNs;
            long lastArrivalMonoNs;
            int highestSeenDataFrag = -1;
            int standardShardLength;
            final Map<Integer, byte[]> dataShards = new HashMap<>();
            final Map<Integer, Map<Integer, byte[]>> parityByBlock = new HashMap<>();
            final Map<Integer, ParityDescriptor> descriptorsByBlock = new HashMap<>();
            final Map<Integer, Integer> nackCountByFrag = new HashMap<>();
            final Map<Integer, Long> lastNackMonoNsByFrag = new HashMap<>();
            boolean recoveredByFec;

            FrameAssembly(long frameId, boolean isKeyframe, long sendTimestampUs, long nowMonoNs) {
                this.frameId = frameId;
                this.isKeyframe = isKeyframe;
                this.sendTimestampUs = sendTimestampUs;
                this.firstArrivalMonoNs = nowMonoNs;
                this.lastArrivalMonoNs = nowMonoNs;
            }
        }

        private final Map<Long, FrameAssembly> frames = new TreeMap<>();
        private Long lastCompletedFrameId = null;
        private boolean needsKeyframeRequest = false;

        public boolean consumeKeyframeRequestFlag() {
            boolean flag = needsKeyframeRequest;
            needsKeyframeRequest = false;
            return flag;
        }

        public FrameEnvelope ingest(AuthenticatedPacket packet, long nowMonoNs) {
            evictExpired(nowMonoNs);
            Header header = packet.header;
            if (header.packetType != PACKET_VIDEO_DATA && header.packetType != PACKET_VIDEO_PARITY) {
                return null;
            }
            long frameId = header.frameId;
            if (lastCompletedFrameId != null && !isNewerFrame(frameId, lastCompletedFrameId)) {
                return null;
            }
            if (!frames.containsKey(frameId) && frames.size() >= MAX_CONCURRENT_FRAMES) {
                Long oldestId = frames.keySet().iterator().next();
                frames.remove(oldestId);
                needsKeyframeRequest = true;
            }

            boolean isKeyframe = (header.flags & FLAG_KEYFRAME) != 0;
            FrameAssembly assembly = frames.get(frameId);
            if (assembly == null) {
                assembly = new FrameAssembly(frameId, isKeyframe, header.sendTimeUs, nowMonoNs);
                frames.put(frameId, assembly);
            }
            assembly.lastArrivalMonoNs = nowMonoNs;
            if (isKeyframe) {
                assembly.isKeyframe = true;
            }

            if (header.packetType == PACKET_VIDEO_DATA) {
                int totalCount = header.fragCount;
                int fragIdx = header.fragIndex;
                if (totalCount < 1
                        || totalCount > MAX_FRAGMENTS_PER_FRAME
                        || fragIdx >= totalCount) {
                    return null;
                }
                if (assembly.expectedDataCount == 0) {
                    assembly.expectedDataCount = totalCount;
                } else if (assembly.expectedDataCount != totalCount) {
                    return null;
                }
                assembly.dataShards.put(fragIdx, packet.payload);
                if (fragIdx > assembly.highestSeenDataFrag) {
                    assembly.highestSeenDataFrag = fragIdx;
                }
                if (fragIdx < totalCount - 1 || totalCount == 1) {
                    assembly.standardShardLength =
                            Math.max(assembly.standardShardLength, packet.payload.length);
                }
            } else {
                ParityDescriptor descriptor =
                        ParityDescriptor.decode(header.fragIndex, header.fragCount);
                if (descriptor == null) {
                    return null;
                }
                assembly.descriptorsByBlock.put(descriptor.blockIndex, descriptor);
                assembly.parityByBlock
                        .computeIfAbsent(descriptor.blockIndex, k -> new HashMap<>())
                        .put(descriptor.parityIndexInBlock, packet.payload);
                assembly.standardShardLength =
                        Math.max(assembly.standardShardLength, packet.payload.length);
                if (assembly.expectedDataCount == 0 && descriptor.blockIndex == 0) {
                    assembly.expectedDataCount = descriptor.blockDataCount;
                }
            }

            tryRecoverBlocksWithFec(assembly);

            if (assembly.expectedDataCount > 0
                    && assembly.dataShards.size() == assembly.expectedDataCount) {
                frames.remove(frameId);
                FrameEnvelope completed = buildFrameEnvelope(assembly);
                if (completed != null) {
                    lastCompletedFrameId = frameId;
                    Iterator<Long> it = frames.keySet().iterator();
                    while (it.hasNext()) {
                        long otherId = it.next();
                        if (!isNewerFrame(otherId, frameId)) {
                            it.remove();
                        }
                    }
                    return completed;
                }
            }
            return null;
        }

        public List<NackPayload> pollNacks(long nowMonoNs, long rttUs) {
            evictExpired(nowMonoNs);
            if (rttUs > MAX_RTT_FOR_NACK_US) {
                return Collections.emptyList();
            }
            List<NackPayload> result = new ArrayList<>();
            for (FrameAssembly assembly : frames.values()) {
                if (assembly.expectedDataCount <= 1) {
                    continue;
                }
                boolean outOfOrderTrigger = assembly.highestSeenDataFrag > 0;
                boolean timerTrigger = (nowMonoNs - assembly.firstArrivalMonoNs) >= NACK_REORDER_DELAY_NS;
                if (!outOfOrderTrigger && !timerTrigger) {
                    continue;
                }
                int searchLimit = timerTrigger
                        ? assembly.expectedDataCount
                        : (assembly.highestSeenDataFrag + 1);
                Integer baseFrag = null;
                long bitmap = 0L;
                int missingCount = 0;

                for (int idx = 0; idx < searchLimit; idx++) {
                    if (assembly.dataShards.containsKey(idx)) {
                        continue;
                    }
                    int count = assembly.nackCountByFrag.getOrDefault(idx, 0);
                    if (count >= 2) {
                        continue;
                    }
                    Long lastNack = assembly.lastNackMonoNsByFrag.get(idx);
                    if (lastNack != null && (nowMonoNs - lastNack) < NACK_COOLDOWN_NS) {
                        continue;
                    }
                    if (baseFrag == null) {
                        baseFrag = idx;
                    }
                    int bitOffset = idx - baseFrag;
                    if (bitOffset >= 64) {
                        break;
                    }
                    bitmap |= (1L << bitOffset);
                    missingCount++;
                    assembly.nackCountByFrag.put(idx, count + 1);
                    assembly.lastNackMonoNsByFrag.put(idx, nowMonoNs);
                }

                if (baseFrag != null && missingCount > 0 && bitmap != 0L) {
                    result.add(new NackPayload(
                            assembly.frameId, baseFrag, missingCount, bitmap, rttUs));
                }
            }
            return result;
        }

        private void tryRecoverBlocksWithFec(FrameAssembly assembly) {
            int strideSize = GF256.MAX_DATA_SHARDS_PER_BLOCK;
            for (Map.Entry<Integer, ParityDescriptor> entry : assembly.descriptorsByBlock.entrySet()) {
                int blockIdx = entry.getKey();
                ParityDescriptor descriptor = entry.getValue();
                Map<Integer, byte[]> blockParities = assembly.parityByBlock.get(blockIdx);
                if (blockParities == null || blockParities.isEmpty()) {
                    continue;
                }
                int startFrag = blockIdx * strideSize;
                Map<Integer, byte[]> presentData = new HashMap<>();
                for (int col = 0; col < descriptor.blockDataCount; col++) {
                    byte[] shard = assembly.dataShards.get(startFrag + col);
                    if (shard != null) {
                        presentData.put(col, shard);
                    }
                }
                int missingCount = descriptor.blockDataCount - presentData.size();
                if (missingCount <= 0 || blockParities.size() < missingCount) {
                    continue;
                }
                byte[] sampleParity = blockParities.values().iterator().next();
                int shardStride = sampleParity != null
                        ? sampleParity.length
                        : assembly.standardShardLength;
                if (shardStride <= 0) {
                    continue;
                }
                Map<Integer, byte[]> recovered = FecCoder.recoverBlockDataShards(
                        descriptor.blockDataCount,
                        descriptor.lastDataShardLength,
                        shardStride,
                        presentData,
                        blockParities);
                if (recovered != null && !recovered.isEmpty()) {
                    for (Map.Entry<Integer, byte[]> rec : recovered.entrySet()) {
                        assembly.dataShards.put(startFrag + rec.getKey(), rec.getValue());
                    }
                    assembly.recoveredByFec = true;
                }
            }
        }

        private FrameEnvelope buildFrameEnvelope(FrameAssembly assembly) {
            int totalBytes = 0;
            for (int idx = 0; idx < assembly.expectedDataCount; idx++) {
                byte[] shard = assembly.dataShards.get(idx);
                if (shard == null) {
                    return null;
                }
                totalBytes += shard.length;
            }
            if (totalBytes <= FRAME_METADATA_PREFIX_BYTES
                    || totalBytes > FRAME_METADATA_PREFIX_BYTES + MAX_FRAME_BYTES) {
                return null;
            }
            byte[] combined = new byte[totalBytes];
            int offset = 0;
            for (int idx = 0; idx < assembly.expectedDataCount; idx++) {
                byte[] shard = assembly.dataShards.get(idx);
                System.arraycopy(shard, 0, combined, offset, shard.length);
                offset += shard.length;
            }
            long captureMs = readInt64(combined, 0);
            long configVer = readInt64(combined, 8);
            byte[] annexB = Arrays.copyOfRange(combined, FRAME_METADATA_PREFIX_BYTES, combined.length);
            return new FrameEnvelope(
                    assembly.frameId,
                    assembly.isKeyframe,
                    captureMs,
                    assembly.sendTimestampUs,
                    configVer,
                    annexB,
                    assembly.firstArrivalMonoNs,
                    assembly.recoveredByFec);
        }

        private void evictExpired(long nowMonoNs) {
            Iterator<Map.Entry<Long, FrameAssembly>> it = frames.entrySet().iterator();
            while (it.hasNext()) {
                FrameAssembly assembly = it.next().getValue();
                if ((nowMonoNs - assembly.firstArrivalMonoNs) > REASSEMBLY_TIMEOUT_NS) {
                    it.remove();
                    needsKeyframeRequest = true;
                }
            }
        }

        public static boolean isNewerFrame(long candidate, long reference) {
            if (candidate == reference) {
                return false;
            }
            int diff = (int) (candidate - reference);
            return diff > 0;
        }
    }

    /** Bounded 4-frame jitter buffer with 35ms deadline matching {@code UDPJitterBuffer}. */
    public static final class JitterBuffer {
        public static final int MAX_BUFFERED_FRAMES = 4;
        public static final long FRAME_HOLD_DEADLINE_NS = 35_000_000L;

        public static final class PollResult {
            public final List<FrameEnvelope> deliverable;
            public final boolean needsKeyframe;

            public PollResult(List<FrameEnvelope> deliverable, boolean needsKeyframe) {
                this.deliverable = deliverable;
                this.needsKeyframe = needsKeyframe;
            }
        }

        private final Map<Long, FrameEnvelope> buffered = new TreeMap<>();
        private Long lastDecodedFrameId = null;

        public PollResult insert(FrameEnvelope frame, long nowMonoNs) {
            if (lastDecodedFrameId != null
                    && !Reassembler.isNewerFrame(frame.frameId, lastDecodedFrameId)) {
                return new PollResult(Collections.emptyList(), false);
            }
            buffered.put(frame.frameId, frame);
            while (buffered.size() > MAX_BUFFERED_FRAMES) {
                Long oldestKey = buffered.keySet().iterator().next();
                buffered.remove(oldestKey);
            }
            return pollDeliverable(nowMonoNs);
        }

        public PollResult pollDeliverable(long nowMonoNs) {
            List<FrameEnvelope> deliverable = new ArrayList<>();
            boolean needsKeyframe = false;

            while (!buffered.isEmpty()) {
                List<Long> sortedIds = new ArrayList<>(buffered.keySet());
                for (int i = sortedIds.size() - 1; i >= 0; i--) {
                    FrameEnvelope candidate = buffered.get(sortedIds.get(i));
                    if (candidate != null && candidate.isKeyframe) {
                        long kfId = candidate.frameId;
                        if (lastDecodedFrameId == null || kfId != ((lastDecodedFrameId + 1) & 0xFFFF_FFFFL)) {
                            Iterator<Long> it = buffered.keySet().iterator();
                            while (it.hasNext()) {
                                long id = it.next();
                                if (id != kfId && !Reassembler.isNewerFrame(id, kfId)) {
                                    it.remove();
                                }
                            }
                            buffered.remove(kfId);
                            lastDecodedFrameId = kfId;
                            deliverable.add(candidate);
                            break;
                        }
                    }
                }
                if (buffered.isEmpty()) {
                    break;
                }
                Long nextId = buffered.keySet().iterator().next();
                FrameEnvelope nextFrame = buffered.get(nextId);
                if (nextFrame == null) {
                    break;
                }
                if (lastDecodedFrameId == null) {
                    if (nextFrame.isKeyframe || nextId == 1L) {
                        buffered.remove(nextId);
                        lastDecodedFrameId = nextId;
                        deliverable.add(nextFrame);
                        continue;
                    }
                    if ((nowMonoNs - nextFrame.firstArrivalMonoNs) >= FRAME_HOLD_DEADLINE_NS) {
                        buffered.remove(nextId);
                        needsKeyframe = true;
                        continue;
                    }
                    break;
                }

                long expectedNext = (lastDecodedFrameId + 1L) & 0xFFFF_FFFFL;
                if (nextId == expectedNext) {
                    buffered.remove(nextId);
                    lastDecodedFrameId = nextId;
                    deliverable.add(nextFrame);
                    continue;
                }

                if ((nowMonoNs - nextFrame.firstArrivalMonoNs) >= FRAME_HOLD_DEADLINE_NS) {
                    buffered.remove(nextId);
                    lastDecodedFrameId = nextId;
                    deliverable.add(nextFrame);
                    needsKeyframe = true;
                    continue;
                }
                break;
            }
            return new PollResult(deliverable, needsKeyframe);
        }

        public void reset() {
            buffered.clear();
            lastDecodedFrameId = null;
        }
    }

    /** Receiver-side 5ms packet-burst arrival-gradient tracker matching {@code UDPReceiverArrivalEstimator}. */
    public static final class ArrivalEstimator {
        public static final long BURST_WINDOW_US = 5_000L;
        public static final long FEEDBACK_INTERVAL_NS = 30_000_000L;

        private long currentBurstSendTimeUs;
        private long currentBurstArrivalUs;
        private boolean hasCurrentBurst = false;
        private Long previousBurstSendTimeUs = null;
        private Long previousBurstArrivalUs = null;

        private int smoothedGradientUs = 0;
        private long highestSeq = 0;
        private long firstSeqInWindow = 0;
        private boolean hasPacketsInWindow = false;
        private long receivedInWindow = 0;
        private long latestSendTimeUs = 0;
        private long lastFeedbackMonoNs = 0;

        public void recordPacket(long extendedSequence, long sendTimeUs, long arrivalMonoNs) {
            long arrivalUs = arrivalMonoNs / 1_000L;
            latestSendTimeUs = sendTimeUs;
            if (!hasPacketsInWindow) {
                hasPacketsInWindow = true;
                firstSeqInWindow = extendedSequence;
                highestSeq = extendedSequence;
            } else if (extendedSequence > highestSeq) {
                highestSeq = extendedSequence;
            }
            receivedInWindow++;

            if (!hasCurrentBurst) {
                hasCurrentBurst = true;
                currentBurstSendTimeUs = sendTimeUs;
                currentBurstArrivalUs = arrivalUs;
                return;
            }

            int sendDelta = (int) (sendTimeUs - currentBurstSendTimeUs);
            if (sendDelta >= 0 && sendDelta <= BURST_WINDOW_US) {
                currentBurstArrivalUs = arrivalUs;
                currentBurstSendTimeUs = sendTimeUs;
            } else {
                if (previousBurstSendTimeUs != null && previousBurstArrivalUs != null) {
                    long dSend = (int) (currentBurstSendTimeUs - previousBurstSendTimeUs);
                    long dArr = currentBurstArrivalUs - previousBurstArrivalUs;
                    long rawGrad = Math.max(-250_000L, Math.min(250_000L, dArr - dSend));
                    smoothedGradientUs = (int) Math.round(0.70 * smoothedGradientUs + 0.30 * rawGrad);
                }
                previousBurstSendTimeUs = currentBurstSendTimeUs;
                previousBurstArrivalUs = currentBurstArrivalUs;
                currentBurstSendTimeUs = sendTimeUs;
                currentBurstArrivalUs = arrivalUs;
            }
        }

        public FeedbackPayload pollFeedbackIfDue(
                long nowMonoNs, int decodeQueueMs, int renderFps) {
            if (!hasPacketsInWindow) {
                return null;
            }
            if (lastFeedbackMonoNs > 0 && (nowMonoNs - lastFeedbackMonoNs) < FEEDBACK_INTERVAL_NS) {
                return null;
            }
            if (hasCurrentBurst && previousBurstSendTimeUs != null && previousBurstArrivalUs != null) {
                long dSend = (int) (currentBurstSendTimeUs - previousBurstSendTimeUs);
                long dArr = currentBurstArrivalUs - previousBurstArrivalUs;
                long rawGrad = Math.max(-250_000L, Math.min(250_000L, dArr - dSend));
                smoothedGradientUs = (int) Math.round(0.70 * smoothedGradientUs + 0.30 * rawGrad);
                previousBurstSendTimeUs = currentBurstSendTimeUs;
                previousBurstArrivalUs = currentBurstArrivalUs;
            }
            long expected = highestSeq >= firstSeqInWindow
                    ? (highestSeq - firstSeqInWindow + 1L)
                    : receivedInWindow;
            long lost = expected > receivedInWindow ? (expected - receivedInWindow) : 0L;
            FeedbackPayload payload = new FeedbackPayload(
                    highestSeq,
                    receivedInWindow,
                    lost,
                    smoothedGradientUs,
                    decodeQueueMs,
                    renderFps,
                    latestSendTimeUs);
            lastFeedbackMonoNs = nowMonoNs;
            firstSeqInWindow = highestSeq + 1L;
            receivedInWindow = 0;
            hasPacketsInWindow = false;
            return payload;
        }
    }

    static void writeUInt16(byte[] out, int offset, int value) {
        out[offset] = (byte) ((value >>> 8) & 0xFF);
        out[offset + 1] = (byte) (value & 0xFF);
    }

    static void writeUInt32(byte[] out, int offset, long value) {
        out[offset] = (byte) ((value >>> 24) & 0xFFL);
        out[offset + 1] = (byte) ((value >>> 16) & 0xFFL);
        out[offset + 2] = (byte) ((value >>> 8) & 0xFFL);
        out[offset + 3] = (byte) (value & 0xFFL);
    }

    static void writeInt64(byte[] out, int offset, long value) {
        ByteBuffer.wrap(out, offset, 8).order(ByteOrder.BIG_ENDIAN).putLong(value);
    }

    static int readUInt16(byte[] data, int offset) {
        return (Byte.toUnsignedInt(data[offset]) << 8)
                | Byte.toUnsignedInt(data[offset + 1]);
    }

    static long readUInt32(byte[] data, int offset) {
        return (Byte.toUnsignedLong(data[offset]) << 24)
                | (Byte.toUnsignedLong(data[offset + 1]) << 16)
                | (Byte.toUnsignedLong(data[offset + 2]) << 8)
                | Byte.toUnsignedLong(data[offset + 3]);
    }

    static long readInt64(byte[] data, int offset) {
        return ByteBuffer.wrap(data, offset, 8).order(ByteOrder.BIG_ENDIAN).getLong();
    }
}

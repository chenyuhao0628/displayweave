package app.opendisplay.android;

import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.function.LongSupplier;

/** Atomic pairing policy. Token state is memory-only; trust is committed before admission. */
public final class SecurePairingState {
    public interface Persistence { void save(byte[] encoded) throws IOException; }
    public static final class Peer {
        public final String installID, name, certificateSHA256;
        public final boolean revoked;
        Peer(String id, String name, String pin, boolean revoked) {
            this.installID = id; this.name = name; this.certificateSHA256 = pin; this.revoked = revoked;
        }
    }
    public final String localID, localFingerprint;
    private final LongSupplier clock;
    private final Persistence persistence;
    private Map<String, Peer> records = new LinkedHashMap<>();
    private byte[] token;
    private long began, expires;
    private int failures;

    public SecurePairingState(String localID, String localFingerprint, byte[] persisted,
                               LongSupplier clock, Persistence persistence) throws IOException {
        if (!SecurePairingProtocol.validID(localID)) throw new IOException("invalid local installation identity");
        SecurePairingProtocol.fingerprintBytes(localFingerprint);
        this.localID = localID; this.localFingerprint = localFingerprint;
        this.clock = clock; this.persistence = persistence;
        if (persisted != null) {
            if (persisted.length > 128 * 1024) throw new IOException("trust store too large");
            SecurePairingProtocol.Reader reader = new SecurePairingProtocol.Reader(persisted);
            SecurePairingProtocol.magic(reader, "DWS1");
            byte[] countBytes = reader.take(2); int count = (countBytes[0] & 255) << 8 | (countBytes[1] & 255);
            if (count > 128) throw new IOException("trust store exceeds identity bound");
            for (int n = 0; n < count; n++) {
                String id = reader.string(256), name = reader.string(128), pin = SecurePairingProtocol.hex(reader.take(32));
                int revoked = reader.take(1)[0] & 255;
                if (revoked > 1 || records.containsKey(id)) throw new IOException("corrupt trust store");
                validatePeer(id, name, pin);
                records.put(id, new Peer(id, name, pin, revoked == 1));
            }
            if (!reader.finished()) throw new IOException("trailing trust-store bytes");
        }
    }

    public synchronized List<Peer> peers() {
        List<Peer> result = new ArrayList<>(records.values()); result.sort(Comparator.comparing(peer -> peer.installID)); return result;
    }
    public synchronized boolean pairingOpen() {
        long now = clock.getAsLong();
        if (token == null || now < began || now >= expires || failures >= 5) { token = null; return false; }
        return true;
    }
    public synchronized boolean hasPairingHistory(String id) { return records.containsKey(id); }
    public synchronized Peer trustedPeer(String id) {
        Peer peer = records.get(id); return peer != null && !peer.revoked ? peer : null;
    }
    public synchronized boolean acceptsTLS(String pin) {
        try { SecurePairingProtocol.fingerprintBytes(pin); } catch (IOException error) { return false; }
        for (Peer peer : records.values()) if (!peer.revoked && peer.certificateSHA256.equals(pin)) return true;
        return pairingOpen();
    }
    public synchronized SecurePairingProtocol.Invitation startPairing() throws IOException {
        long now = clock.getAsLong();
        if (now < 0 || now > Long.MAX_VALUE - 120000) throw new IOException("monotonic clock unavailable");
        token = SecurePairingProtocol.randomToken(); began = now; expires = now + 120000; failures = 0;
        return new SecurePairingProtocol.Invitation(localID, localFingerprint, token);
    }
    public synchronized void stopPairing() { token = null; }

    public synchronized Peer authenticate(SecurePairingProtocol.Auth auth, String pin) throws IOException {
        validatePeer(auth.installID, auth.name, pin);
        Peer existing = records.get(auth.installID);
        if (existing != null && !existing.revoked) {
            if (!existing.certificateSHA256.equals(pin)) throw new IOException("peer certificate changed; revoke and pair again");
            return existing;
        }
        if (!pairingOpen() || !SecurePairingProtocol.equalToken(token, auth.token)) {
            if (pairingOpen() && ++failures >= 5) token = null;
            throw new IOException("pairing invitation invalid or expired; request a new invitation");
        }
        Peer peer = storePeer(auth.installID, auth.name, pin);
        token = null;
        return peer;
    }
    public synchronized void revoke(String id) throws IOException {
        Peer peer = records.get(id);
        if (peer == null) return;
        Map<String, Peer> next = new LinkedHashMap<>(records);
        next.put(id, new Peer(id, peer.name, peer.certificateSHA256, true));
        commit(next); token = null;
    }
    private void validatePeer(String id, String name, String pin) throws IOException {
        if (!SecurePairingProtocol.validID(id) || id.equals(localID) || !SecurePairingProtocol.validName(name, 128)
                || (!records.containsKey(id) && records.size() >= 128)) throw new IOException("invalid peer or trust store full");
        SecurePairingProtocol.fingerprintBytes(pin);
        for (Peer peer : records.values()) {
            if (!peer.installID.equals(id) && peer.certificateSHA256.equals(pin)) throw new IOException("certificate cannot alias another installation");
        }
    }
    private Peer storePeer(String id, String name, String pin) throws IOException {
        validatePeer(id, name, pin);
        Peer peer = new Peer(id, name, pin, false);
        Map<String, Peer> next = new LinkedHashMap<>(records); next.put(id, peer);
        commit(next); return peer;
    }
    private void commit(Map<String, Peer> next) throws IOException {
        ByteArrayOutputStream output = new ByteArrayOutputStream(); output.write("DWS1".getBytes(StandardCharsets.US_ASCII));
        output.write(next.size() >> 8); output.write(next.size() & 255);
        List<Peer> peers = new ArrayList<>(next.values()); peers.sort(Comparator.comparing(peer -> peer.installID));
        for (Peer peer : peers) {
            SecurePairingProtocol.string(output, peer.installID); SecurePairingProtocol.string(output, peer.name);
            output.write(SecurePairingProtocol.fingerprintBytes(peer.certificateSHA256)); output.write(peer.revoked ? 1 : 0);
        }
        byte[] data = output.toByteArray();
        if (data.length > 128 * 1024) throw new IOException("trust store too large");
        persistence.save(data);
        records = next;
    }
}

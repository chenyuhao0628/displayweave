package app.opendisplay.android;

import java.io.BufferedInputStream;
import java.io.BufferedOutputStream;
import java.io.DataInputStream;
import java.io.DataOutputStream;
import java.io.IOException;
import java.net.Socket;
import java.security.GeneralSecurityException;
import java.security.PrivateKey;
import java.security.cert.Certificate;
import java.security.cert.X509Certificate;
import javax.net.ssl.SSLSocket;

/** Blocking work for a bounded admission worker, before an application session exists.
 * The owning transport closes the raw socket at the total handshake/admission deadline.
 */
public final class SecureSocketAdmission {
    final SecurePairingState pairing;
    private final PrivateKey key;
    private final X509Certificate certificate;

    public SecureSocketAdmission(PrivateKey key, X509Certificate certificate, SecurePairingState pairing) {
        this.key = java.util.Objects.requireNonNull(key);
        this.certificate = java.util.Objects.requireNonNull(certificate);
        this.pairing = java.util.Objects.requireNonNull(pairing);
    }

    static final class Accepted {
        final SSLSocket socket;
        final BufferedInputStream input;
        final BufferedOutputStream output;
        final SecurePairingState.Peer peer;
        Accepted(SSLSocket socket, BufferedInputStream input, BufferedOutputStream output, SecurePairingState.Peer peer) {
            this.socket = socket; this.input = input; this.output = output; this.peer = peer;
        }
    }

    Accepted authenticate(Socket raw) throws IOException, GeneralSecurityException {
        SSLSocket socket = SecureTls.wrap(raw, key, certificate, pairing::acceptsTLS);
        try {
            socket.setSoTimeout(10000);
            socket.startHandshake();
            Certificate[] chain = socket.getSession().getPeerCertificates();
            if (chain.length != 1 || !(chain[0] instanceof X509Certificate)) throw new IOException("missing TLS peer identity");
            String fingerprint = SecureTls.fingerprint((X509Certificate) chain[0]);
            socket.getSession().invalidate();
            // The same buffers are handed to the application. Any TLS bytes
            // prefetched past the auth frame remain owned by this connection.
            BufferedInputStream input = new BufferedInputStream(socket.getInputStream());
            BufferedOutputStream output = new BufferedOutputStream(socket.getOutputStream());
            SecurePairingProtocol.Auth auth = SecurePairingProtocol.Auth.decode(readFrame(input));
            SecurePairingState.Peer peer = pairing.authenticate(auth, fingerprint);
            writeFrame(output, SecurePairingProtocol.ready(pairing.localID));
            if (!stillTrusted(peer)) throw new IOException("peer revoked during admission");
            socket.setSoTimeout(0);
            return new Accepted(socket, input, output, peer);
        } catch (IOException | GeneralSecurityException | RuntimeException error) {
            try { raw.close(); } catch (IOException ignored) { }
            try { socket.close(); } catch (IOException ignored) { }
            throw error;
        }
    }

    boolean stillTrusted(SecurePairingState.Peer peer) {
        if (peer == null) return false;
        SecurePairingState.Peer current = pairing.trustedPeer(peer.installID);
        return current != null && current.certificateSHA256.equals(peer.certificateSHA256);
    }

    static byte[] readFrame(java.io.InputStream input) throws IOException {
        DataInputStream data = new DataInputStream(input);
        int length = data.readInt();
        if (length <= 0 || length > SecurePairingProtocol.MAX_AUTH_BYTES) throw new IOException("invalid admission frame length");
        byte[] payload = new byte[length];
        data.readFully(payload);
        return payload;
    }

    static void writeFrame(java.io.OutputStream output, byte[] payload) throws IOException {
        if (payload == null || payload.length == 0 || payload.length > SecurePairingProtocol.MAX_AUTH_BYTES) throw new IOException("invalid admission frame length");
        DataOutputStream data = new DataOutputStream(output);
        data.writeInt(payload.length); data.write(payload); data.flush();
    }
}

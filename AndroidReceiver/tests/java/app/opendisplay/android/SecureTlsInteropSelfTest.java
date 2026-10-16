package app.opendisplay.android;

import java.io.InputStream;
import java.net.ServerSocket;
import java.net.Socket;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.security.KeyStore;
import java.security.PrivateKey;
import java.security.cert.CertificateFactory;
import java.security.cert.X509Certificate;
import java.util.Arrays;
import javax.net.ssl.SSLSocket;

/** Real JSSE interoperability fixture. Keys are generated into a temporary test directory. */
public final class SecureTlsInteropSelfTest {
    public static void main(String[] args) throws Exception {
        KeyStore keys = KeyStore.getInstance("PKCS12");
        try (InputStream input = Files.newInputStream(Path.of(args[1]))) {
            keys.load(input, "fixture-password".toCharArray());
        }
        PrivateKey key = (PrivateKey) keys.getKey("transport", "fixture-password".toCharArray());
        X509Certificate cert = (X509Certificate) keys.getCertificate("transport");
        if ("prepare".equals(args[0])) {
            cert = TransportCertificate.create(key, cert.getPublicKey());
            keys.setKeyEntry("transport", key, "fixture-password".toCharArray(), new java.security.cert.Certificate[]{cert});
            try (java.io.OutputStream output = Files.newOutputStream(Path.of(args[1]))) {
                keys.store(output, "fixture-password".toCharArray());
            }
            Files.write(Path.of(args[2]), cert.getEncoded());
            System.out.println("Java-generated TLS certificate extensions and self-signature PASS");
            return;
        }
        byte[] probe = "probe".getBytes(StandardCharsets.UTF_8);
        if ("client".equals(args[0])) {
            String expected = args[3];
            try (SSLSocket socket = (SSLSocket) SecureTls.context(key, cert, expected::equals)
                    .getSocketFactory().createSocket("127.0.0.1", Integer.parseInt(args[2]))) {
                SecureTls.configure(socket, true);
                socket.setSoTimeout(5000);
                socket.startHandshake();
                socket.getSession().invalidate();
                socket.getOutputStream().write(probe);
                socket.getOutputStream().flush();
                if (!Arrays.equals(probe, socket.getInputStream().readNBytes(5))) throw new AssertionError("TLS echo mismatch");
                System.out.println("Java client pinned mutual TLS PASS");
            }
        } else if ("server".equals(args[0])) {
            X509Certificate client;
            try (InputStream input = Files.newInputStream(Path.of(args[2]))) {
                client = (X509Certificate) CertificateFactory.getInstance("X.509").generateCertificate(input);
            }
            String expected = SecureTls.fingerprint(client);
            try (ServerSocket listener = new ServerSocket(0, 2, java.net.InetAddress.getLoopbackAddress())) {
                listener.setSoTimeout(10000);
                Files.writeString(Path.of(args[3]), Integer.toString(listener.getLocalPort()));
                try (Socket accepted = listener.accept();
                     SSLSocket socket = SecureTls.wrap(accepted, key, cert, expected::equals)) {
                    socket.setSoTimeout(5000);
                    socket.startHandshake();
                    socket.getSession().invalidate();
                    if (!Arrays.equals(probe, socket.getInputStream().readNBytes(5))) throw new AssertionError("TLS probe mismatch");
                    socket.getOutputStream().write(probe);
                    socket.getOutputStream().flush();
                    System.out.println("Java server pinned mutual TLS PASS");
                }
            }
        } else { throw new AssertionError("unsupported fixture role"); }
    }
}

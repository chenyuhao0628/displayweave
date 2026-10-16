package app.opendisplay.android;

import java.io.IOException;
import java.net.Socket;
import java.security.GeneralSecurityException;
import java.security.MessageDigest;
import java.security.Principal;
import java.security.PrivateKey;
import java.security.SecureRandom;
import java.security.cert.CertificateException;
import java.security.cert.X509Certificate;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;
import java.util.function.Predicate;
import javax.net.ssl.KeyManager;
import javax.net.ssl.SSLContext;
import javax.net.ssl.SSLEngine;
import javax.net.ssl.SSLSocket;
import javax.net.ssl.TrustManager;
import javax.net.ssl.X509ExtendedKeyManager;
import javax.net.ssl.X509TrustManager;

/** Platform TLS with an application-owned transport identity and full certificate pin. */
public final class SecureTls {
    private SecureTls() { }
    private static final String[] CIPHERS = {
        "TLS_AES_128_GCM_SHA256", "TLS_AES_256_GCM_SHA384", "TLS_CHACHA20_POLY1305_SHA256",
        "TLS_ECDHE_ECDSA_WITH_AES_128_GCM_SHA256", "TLS_ECDHE_ECDSA_WITH_AES_256_GCM_SHA384"
    };

    public static String fingerprint(X509Certificate certificate) throws CertificateException {
        try {
            byte[] encoded = certificate.getEncoded();
            if (encoded.length > 8192) throw new CertificateException("transport certificate too large");
            byte[] digest = MessageDigest.getInstance("SHA-256").digest(encoded);
            StringBuilder result = new StringBuilder(64);
            for (byte value : digest) result.append(String.format(java.util.Locale.ROOT, "%02x", value & 255));
            return result.toString();
        } catch (GeneralSecurityException error) { throw new CertificateException("certificate fingerprint failed", error); }
    }

    public static void validate(X509Certificate[] chain, boolean server,
                                Predicate<String> acceptedFingerprint) throws CertificateException {
        if (chain == null || chain.length != 1) throw new CertificateException("expected one pinned transport certificate");
        X509Certificate cert = chain[0];
        if (!acceptedFingerprint.test(fingerprint(cert))) throw new CertificateException("unknown or revoked transport identity");
        cert.checkValidity();
        if (!"EC".equals(cert.getPublicKey().getAlgorithm()) || cert.hasUnsupportedCriticalExtension()
                || !cert.getSubjectX500Principal().equals(cert.getIssuerX500Principal())) {
            throw new CertificateException("unsupported transport certificate");
        }
        boolean[] usage = cert.getKeyUsage();
        List<String> extended = cert.getExtendedKeyUsage();
        if ((usage != null && (usage.length == 0 || !usage[0])) || (extended != null
                && !extended.contains(server ? "1.3.6.1.5.5.7.3.1" : "1.3.6.1.5.5.7.3.2"))) {
            throw new CertificateException("certificate cannot authenticate this TLS role");
        }
        try { cert.verify(cert.getPublicKey()); }
        catch (GeneralSecurityException error) { throw new CertificateException("invalid self signature", error); }
    }

    /** New context for each connection: no cross-connection session cache/resumption. */
    public static SSLContext context(PrivateKey privateKey, X509Certificate certificate,
                                     Predicate<String> acceptedFingerprint) throws GeneralSecurityException {
        SSLContext context = SSLContext.getInstance("TLS");
        context.init(new KeyManager[]{new IdentityKeyManager(privateKey, certificate)},
                new TrustManager[]{new X509TrustManager() {
                    public X509Certificate[] getAcceptedIssuers() { return new X509Certificate[0]; }
                    public void checkClientTrusted(X509Certificate[] chain, String auth) throws CertificateException {
                        validate(chain, false, acceptedFingerprint);
                    }
                    public void checkServerTrusted(X509Certificate[] chain, String auth) throws CertificateException {
                        validate(chain, true, acceptedFingerprint);
                    }
                }}, new SecureRandom());
        return context;
    }

    public static void configure(SSLSocket socket, boolean client) {
        socket.setUseClientMode(client);
        socket.setEnabledProtocols(intersection(new String[]{"TLSv1.3", "TLSv1.2"}, socket.getSupportedProtocols()));
        socket.setEnabledCipherSuites(intersection(CIPHERS, socket.getSupportedCipherSuites()));
        if (!client) socket.setNeedClientAuth(true);
    }

    public static SSLSocket wrap(Socket socket, PrivateKey privateKey, X509Certificate certificate,
                                 Predicate<String> acceptedFingerprint) throws IOException, GeneralSecurityException {
        SSLSocket tls = (SSLSocket) context(privateKey, certificate, acceptedFingerprint).getSocketFactory()
                .createSocket(socket, socket.getInetAddress().getHostAddress(), socket.getPort(), true);
        configure(tls, false);
        return tls;
    }

    private static String[] intersection(String[] preferred, String[] supported) {
        List<String> result = new ArrayList<>();
        for (String value : preferred) if (Arrays.asList(supported).contains(value)) result.add(value);
        if (result.isEmpty()) throw new IllegalStateException("TLS 1.2+ ECDHE/AEAD unavailable");
        return result.toArray(new String[0]);
    }

    private static final class IdentityKeyManager extends X509ExtendedKeyManager {
        private final PrivateKey key;
        private final X509Certificate certificate;
        IdentityKeyManager(PrivateKey key, X509Certificate certificate) { this.key = key; this.certificate = certificate; }
        public String[] getClientAliases(String type, Principal[] issuers) { return aliases(type); }
        public String[] getServerAliases(String type, Principal[] issuers) { return aliases(type); }
        private String[] aliases(String type) { return "EC".equals(type) ? new String[]{"transport"} : null; }
        public String chooseClientAlias(String[] types, Principal[] issuers, Socket socket) {
            return Arrays.asList(types).contains("EC") ? "transport" : null;
        }
        public String chooseEngineClientAlias(String[] types, Principal[] issuers, SSLEngine engine) {
            return chooseClientAlias(types, issuers, null);
        }
        public String chooseServerAlias(String type, Principal[] issuers, Socket socket) { return "EC".equals(type) ? "transport" : null; }
        public String chooseEngineServerAlias(String type, Principal[] issuers, SSLEngine engine) { return chooseServerAlias(type, issuers, null); }
        public X509Certificate[] getCertificateChain(String alias) { return "transport".equals(alias) ? new X509Certificate[]{certificate} : null; }
        public PrivateKey getPrivateKey(String alias) { return "transport".equals(alias) ? key : null; }
    }
}

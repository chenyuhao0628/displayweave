package app.opendisplay.android;

import android.content.Context;
import android.content.SharedPreferences;
import android.os.SystemClock;
import android.security.keystore.KeyGenParameterSpec;
import android.security.keystore.KeyProperties;
import java.io.IOException;
import java.io.ByteArrayInputStream;
import java.math.BigInteger;
import java.security.GeneralSecurityException;
import java.security.KeyPairGenerator;
import java.security.KeyStore;
import java.security.PrivateKey;
import java.security.SecureRandom;
import java.security.cert.X509Certificate;
import java.security.cert.CertificateFactory;
import java.security.spec.ECGenParameterSpec;
import java.util.Base64;
import java.util.Date;
import javax.security.auth.x500.X500Principal;

/** Private keys stay in Android Keystore. Public trust metadata stays in the app sandbox. */
public final class AndroidSecurityStore {
    private static final String ALIAS = "displayweave.transport.v1";
    private static AndroidSecurityStore instance;
    public final PrivateKey key;
    public final X509Certificate certificate;
    public final SecurePairingState pairing;
    private final SharedPreferences preferences;

    public static synchronized AndroidSecurityStore get(Context context) throws GeneralSecurityException, IOException {
        if (instance == null) instance = new AndroidSecurityStore(context.getApplicationContext());
        return instance;
    }
    private AndroidSecurityStore(Context context) throws GeneralSecurityException, IOException {
        preferences = context.getSharedPreferences("transport-security-v1", Context.MODE_PRIVATE);
        KeyStore store = KeyStore.getInstance("AndroidKeyStore"); store.load(null);
        boolean recordedIdentity = preferences.getBoolean("identity-created", false);
        boolean created = false;
        if (!store.containsAlias(ALIAS)) {
            if (recordedIdentity || preferences.contains("peers")) throw new GeneralSecurityException("transport identity missing; explicitly reset and pair again");
            long now = System.currentTimeMillis();
            KeyPairGenerator generator = KeyPairGenerator.getInstance(KeyProperties.KEY_ALGORITHM_EC, "AndroidKeyStore");
            generator.initialize(new KeyGenParameterSpec.Builder(ALIAS, KeyProperties.PURPOSE_SIGN | KeyProperties.PURPOSE_VERIFY)
                    .setAlgorithmParameterSpec(new ECGenParameterSpec("secp256r1"))
                    .setDigests(KeyProperties.DIGEST_SHA256, KeyProperties.DIGEST_SHA384)
                    .setCertificateSubject(new X500Principal("CN=DisplayWeave Transport"))
                    .setCertificateSerialNumber(new BigInteger(127, new SecureRandom()).add(BigInteger.ONE))
                    .setCertificateNotBefore(new Date(now - 86400000L))
                    .setCertificateNotAfter(new Date(now + 365L * 86400000L))
                    .setUserAuthenticationRequired(false).build());
            generator.generateKeyPair();
            created = true;
        }
        if (!(store.getKey(ALIAS, null) instanceof PrivateKey) || !(store.getCertificate(ALIAS) instanceof X509Certificate)) {
            throw new GeneralSecurityException("incomplete transport identity; explicitly reset and pair again");
        }
        key = (PrivateKey) store.getKey(ALIAS, null);
        if (created) {
            // The Keystore's generated certificate need not contain TLS EKUs.
            // Sign a standard TLS leaf using that same non-exportable key.
            try {
                certificate = TransportCertificate.create(key, store.getCertificate(ALIAS).getPublicKey());
                if (!preferences.edit().putBoolean("identity-created", true)
                        .putString("certificate", Base64.getEncoder().encodeToString(certificate.getEncoded())).commit()) {
                    throw new IOException("could not persist transport certificate");
                }
            } catch (GeneralSecurityException | IOException error) {
                store.deleteEntry(ALIAS); // only the identity just created by this invocation
                throw error;
            }
        } else {
            String encoded = preferences.getString("certificate", null);
            if (!recordedIdentity || encoded == null || encoded.length() > 12000) throw new GeneralSecurityException("incomplete transport certificate; explicitly reset identity");
            try {
                certificate = (X509Certificate) CertificateFactory.getInstance("X.509").generateCertificate(
                        new ByteArrayInputStream(Base64.getDecoder().decode(encoded)));
                certificate.verify(store.getCertificate(ALIAS).getPublicKey());
            } catch (IllegalArgumentException error) { throw new GeneralSecurityException("corrupt transport certificate", error); }
            if (!java.util.Arrays.equals(certificate.getPublicKey().getEncoded(), store.getCertificate(ALIAS).getPublicKey().getEncoded())) {
                throw new GeneralSecurityException("transport certificate/key mismatch");
            }
        }
        byte[] persisted = null;
        String saved = preferences.getString("peers", null);
        if (saved != null) {
            if (saved.length() > 180000) throw new IOException("trust store too large");
            try { persisted = Base64.getDecoder().decode(saved); }
            catch (IllegalArgumentException error) { throw new IOException("corrupt trust store", error); }
        }
        pairing = new SecurePairingState(InstallId.get(context), SecureTls.fingerprint(certificate), persisted,
                SystemClock::elapsedRealtime, data -> {
            if (!preferences.edit().putString("peers", Base64.getEncoder().encodeToString(data)).commit()) {
                throw new IOException("could not persist peer trust");
            }
        });
    }
}

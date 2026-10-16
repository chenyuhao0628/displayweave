package app.opendisplay.android;

import android.content.Context;
import android.content.SharedPreferences;
import android.os.SystemClock;
import android.security.keystore.KeyGenParameterSpec;
import android.security.keystore.KeyInfo;
import android.security.keystore.KeyProperties;
import java.io.IOException;
import java.io.ByteArrayInputStream;
import java.math.BigInteger;
import java.security.GeneralSecurityException;
import java.security.KeyPairGenerator;
import java.security.KeyFactory;
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
    static final String ALIAS = "displayweave.transport.v1";
    private static final String PREFS = "transport-security-v1";
    private static AndroidSecurityStore instance;
    public final PrivateKey key;
    public final X509Certificate certificate;
    public final SecurePairingState pairing;
    private final SharedPreferences preferences;

    public static synchronized AndroidSecurityStore get(Context context) throws GeneralSecurityException, IOException {
        if (instance == null) instance = new AndroidSecurityStore(context.getApplicationContext());
        return instance;
    }
    public static synchronized AndroidSecurityStore reload(Context context) throws GeneralSecurityException, IOException {
        if (instance != null) instance.pairing.invalidate();
        instance = null;
        return get(context);
    }

    public static synchronized void stopPairingIfLoaded() {
        if (instance != null) instance.pairing.stopPairing();
    }

    /** Explicit action only. Preserve revoked history even when the key is missing. */
    public static synchronized AndroidSecurityStore resetIdentity(Context context) throws GeneralSecurityException, IOException {
        SharedPreferences prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE);
        SecurePairingState state = instance != null ? instance.pairing : new SecurePairingState(
                InstallId.get(context), "0000000000000000000000000000000000000000000000000000000000000000", readPeers(prefs), SystemClock::elapsedRealtime,
                data -> savePeers(prefs, data));
        state.revokeAllAndInvalidate();
        instance = null;
        if (!prefs.edit().putBoolean("reset-pending", true).commit()) throw new IOException("could not record identity reset");
        KeyStore store = KeyStore.getInstance("AndroidKeyStore"); store.load(null);
        store.deleteEntry(ALIAS);
        return get(context);
    }

    private static byte[] readPeers(SharedPreferences preferences) throws IOException {
        String saved = preferences.getString("peers", null);
        if (saved == null) return null;
        if (saved.length() > 180000) throw new IOException("trust store too large");
        try { return Base64.getDecoder().decode(saved); }
        catch (IllegalArgumentException error) { throw new IOException("corrupt trust store", error); }
    }
    private static void savePeers(SharedPreferences preferences, byte[] data) throws IOException {
        if (!preferences.edit().putString("peers", Base64.getEncoder().encodeToString(data)).commit()) {
            throw new IOException("could not persist peer trust");
        }
    }

    private AndroidSecurityStore(Context context) throws GeneralSecurityException, IOException {
        preferences = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE);
        KeyStore store = KeyStore.getInstance("AndroidKeyStore"); store.load(null);
        boolean recordedIdentity = preferences.getBoolean("identity-created", false);
        boolean resetPending = preferences.getBoolean("reset-pending", false);
        if (resetPending) store.deleteEntry(ALIAS); // resume only an explicitly recorded reset
        boolean created = false;
        if (!store.containsAlias(ALIAS)) {
            if (!resetPending && (recordedIdentity || preferences.contains("peers"))) throw new GeneralSecurityException("transport identity missing; explicitly reset and pair again");
            long now = System.currentTimeMillis();
            KeyPairGenerator generator = KeyPairGenerator.getInstance(KeyProperties.KEY_ALGORITHM_EC, "AndroidKeyStore");
            generator.initialize(new KeyGenParameterSpec.Builder(ALIAS, KeyProperties.PURPOSE_SIGN | KeyProperties.PURPOSE_VERIFY)
                    .setAlgorithmParameterSpec(new ECGenParameterSpec("secp256r1"))
                    // Conscrypt hashes the TLS transcript before asking the
                    // Keystore for ECDSA. TLS therefore requires DIGEST_NONE;
                    // SHA-256 remains authorized for our X.509 certificate.
                    .setDigests(KeyProperties.DIGEST_NONE, KeyProperties.DIGEST_SHA256, KeyProperties.DIGEST_SHA384)
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
        KeyInfo info = KeyFactory.getInstance(KeyProperties.KEY_ALGORITHM_EC, "AndroidKeyStore").getKeySpec(key, KeyInfo.class);
        if (!java.util.Arrays.asList(info.getDigests()).contains(KeyProperties.DIGEST_NONE)) {
            throw new GeneralSecurityException("transport key cannot sign TLS; explicitly reset identity and pair again");
        }
        if (created) {
            // The Keystore's generated certificate need not contain TLS EKUs.
            // Sign a standard TLS leaf using that same non-exportable key.
            try {
                certificate = TransportCertificate.create(key, store.getCertificate(ALIAS).getPublicKey());
                if (!preferences.edit().putBoolean("identity-created", true)
                        .putString("certificate", Base64.getEncoder().encodeToString(certificate.getEncoded()))
                        .remove("reset-pending").commit()) {
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
        pairing = new SecurePairingState(InstallId.get(context), SecureTls.fingerprint(certificate), readPeers(preferences),
                SystemClock::elapsedRealtime, data -> savePeers(preferences, data));
    }
}

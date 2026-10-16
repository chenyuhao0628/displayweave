package app.opendisplay.android;

import android.app.Activity;
import android.content.Intent;
import android.os.Bundle;
import java.io.FileOutputStream;
import java.nio.charset.StandardCharsets;
import java.security.KeyStore;

/** Copied only into a disposable test application, never production APKs. */
public final class SecurityRuntimeTestActivity extends Activity {
    private static final java.util.concurrent.atomic.AtomicBoolean started = new java.util.concurrent.atomic.AtomicBoolean();
    private void write(String name, String value) throws Exception {
        try (FileOutputStream file = openFileOutput(name, MODE_PRIVATE)) { file.write(value.getBytes(StandardCharsets.UTF_8)); }
    }
    private String read(String name) throws Exception {
        try (java.io.FileInputStream file = openFileInput(name); java.io.ByteArrayOutputStream output = new java.io.ByteArrayOutputStream()) {
            byte[] buffer = new byte[4096]; int count;
            while ((count = file.read(buffer)) != -1) { output.write(buffer, 0, count); }
            return new String(output.toByteArray(), StandardCharsets.UTF_8);
        }
    }
    private static void expect(boolean value, String message) { if (!value) throw new AssertionError(message); }
    @Override public void onCreate(Bundle saved) {
        super.onCreate(saved);
        if (!started.compareAndSet(false, true)) return;
        new Thread(() -> {
            try {
                android.graphics.drawable.Drawable launcher = getPackageManager().getApplicationIcon(getPackageName());
                expect(launcher instanceof android.graphics.drawable.AdaptiveIconDrawable,
                        "API 26+ package must resolve the adaptive launcher resource");
                android.graphics.drawable.AdaptiveIconDrawable adaptive = (android.graphics.drawable.AdaptiveIconDrawable) launcher;
                expect(adaptive.getForeground() != null && adaptive.getBackground() != null, "adaptive layers missing");
                if ("reload".equals(getIntent().getStringExtra("mode"))) {
                    AndroidSecurityStore restored = AndroidSecurityStore.get(this);
                    expect(read("pin.txt").equals(restored.pairing.localFingerprint), "identity changed across process restart");
                    expect(restored.pairing.hasPairingHistory("keystore-test-peer")
                            && restored.pairing.trustedPeer("keystore-test-peer") == null, "tombstone lost across process restart");
                    // This security fixture is not an updater test; avoid an
                    // unrelated remote-release prompt racing the local UI flow.
                    getSharedPreferences("OpenDisplayAndroid", MODE_PRIVATE).edit()
                            .putLong("updateLastSuccessfulCheck", System.currentTimeMillis()).commit();
                    write("certificate.txt", java.util.Base64.getEncoder().encodeToString(restored.certificate.getEncoded()));
                    write("reload-result.txt", "Keystore process persistence PASS");
                    runOnUiThread(() -> { startActivity(new Intent(this, MainActivity.class)); finish(); });
                } else {
                    AndroidSecurityStore store = AndroidSecurityStore.get(this);
                    expect(store.key.getEncoded() == null, "Keystore private key was exportable");
                    String firstPin = store.pairing.localFingerprint;
                    SecurePairingProtocol.Invitation invite = store.pairing.startPairing();
                    String clientPin = "abababababababababababababababababababababababababababababababab";
                    store.pairing.authenticate(new SecurePairingProtocol.Auth("keystore-test-peer", "Keystore test", invite.token), clientPin);
                    AndroidSecurityStore reopened = AndroidSecurityStore.reload(this);
                    expect(firstPin.equals(reopened.pairing.localFingerprint), "certificate changed on reload");
                    expect(reopened.pairing.trustedPeer("keystore-test-peer") != null,
                            "peer trust missing on reload; record count=" + reopened.pairing.peers().size());
                    expect(!store.pairing.acceptsTLS(clientPin), "old state survived reload");
                    AndroidSecurityStore rotated = AndroidSecurityStore.resetIdentity(this);
                    expect(!firstPin.equals(rotated.pairing.localFingerprint), "reset did not rotate certificate");
                    expect(rotated.pairing.hasPairingHistory("keystore-test-peer") && rotated.pairing.trustedPeer("keystore-test-peer") == null,
                            "reset lost downgrade history");
                    KeyStore keystore = KeyStore.getInstance("AndroidKeyStore"); keystore.load(null);
                    keystore.deleteEntry(AndroidSecurityStore.ALIAS);
                    try { AndroidSecurityStore.reload(this); throw new AssertionError("missing key silently replaced"); }
                    catch (java.security.GeneralSecurityException expected) { }
                    AndroidSecurityStore repaired = AndroidSecurityStore.resetIdentity(this);
                    expect(repaired.pairing.hasPairingHistory("keystore-test-peer"), "repair erased history");
                    write("pin.txt", repaired.pairing.localFingerprint);
                    // Real Android TLS provider, actual deadline/adoption code.
                    SecureTransportSelfTest.run(repaired.key, repaired.certificate);
                    write("result.txt", "Android Keystore identity/trust, nonexportable key, reset, missing-key repair and TLS transport PASS");
                }
            } catch (Throwable failure) {
                try { java.io.StringWriter trace = new java.io.StringWriter(); failure.printStackTrace(new java.io.PrintWriter(trace)); write("error.txt", trace.toString()); } catch (Exception ignored) { }
            }
        }, "isolated-security-test").start();
    }
}

package app.opendisplay.android.update;

public final class UpdatePolicySelfTest {
    private static final String HASH =
            "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef";
    private static final String CERT =
            "89805f045800ea18b56b84b32e8e31b1710a3c7bf3c85fda54d260d1fc6d589d";

    public static void main(String[] args) {
        UpdateManifest manifest = UpdateManifest.parse(validJson());
        expect(manifest.schemaVersion == 1, "schema parsed");
        expect(manifest.versionCode == 123, "version code parsed");
        expect("0.2.0-preview.3".equals(manifest.versionName), "version name parsed");
        expect(UpdatePolicy.isNewer(123, 122), "greater version is newer");
        expect(!UpdatePolicy.isNewer(123, 123), "equal version is not newer");
        expect(UpdatePolicy.shouldCheck(86_400_001L, 1L, false),
                "daily boundary elapsed");
        expect(!UpdatePolicy.shouldCheck(86_400_000L, 1L, false),
                "one millisecond remains");
        expect(UpdatePolicy.shouldCheck(2L, 1L, true), "manual bypasses throttle");
        expect(CERT.equals(UpdatePolicy.normalizeHex(CERT.toUpperCase())),
                "fingerprint normalization is stable");

        expectThrows(() -> UpdateManifest.parse(validJson().replace(
                "https://github.com", "http://github.com")),
                "non-HTTPS APK URL rejected");
        expectThrows(() -> UpdateManifest.parse(validJson().replace(
                "app.opendisplay.android", "app.example.wrong")),
                "wrong package rejected");
        expectThrows(() -> UpdateManifest.parse(validJson().replace(HASH, "xyz")),
                "bad hash rejected");
        expectThrows(() -> UpdateManifest.parse(validJson().replace(
                "\"schemaVersion\":1", "\"schemaVersion\":2")),
                "unknown schema rejected");
        expectThrows(() -> UpdateManifest.parse(validJson().replace(
                "\"minimumSdk\":26", "\"minimumSdk\":25")),
                "unsupported SDK floor rejected");

        System.out.println("UpdatePolicySelfTest PASS");
    }

    private static String validJson() {
        return "{"+
                "\"schemaVersion\":1,"+
                "\"packageName\":\"app.opendisplay.android\","+
                "\"versionCode\":123,"+
                "\"versionName\":\"0.2.0-preview.3\","+
                "\"minimumSdk\":26,"+
                "\"apkUrl\":\"https://github.com/chenyuhao0628/displayweave/releases/"+
                "download/v0.2.0-preview.3/DisplayWeave-Android.apk\","+
                "\"apkSize\":168421,"+
                "\"sha256\":\""+HASH+"\","+
                "\"signingCertificateSha256\":\""+CERT+"\","+
                "\"publishedAt\":\"2026-07-14T00:00:00Z\","+
                "\"releaseNotesUrl\":\"https://github.com/chenyuhao0628/"+
                "displayweave/releases/tag/v0.2.0-preview.3\"}";
    }

    private static void expect(boolean condition, String message) {
        if (!condition) {
            throw new AssertionError(message);
        }
    }

    private static void expectThrows(Runnable action, String message) {
        try {
            action.run();
            throw new AssertionError(message);
        } catch (IllegalArgumentException expected) {
            // Expected validation failure.
        }
    }
}

package app.opendisplay.android.update;

import java.nio.file.Files;
import java.nio.file.Path;

public final class UpdatePolicySelfTest {
    private static final String HASH =
            "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef";
    private static final String CERT =
            "89805f045800ea18b56b84b32e8e31b1710a3c7bf3c85fda54d260d1fc6d589d";

    public static void main(String[] args) throws Exception {
        UpdateManifest manifest = UpdateManifest.parse(validJson());
        expect(manifest.schemaVersion == 1, "schema parsed");
        expect(manifest.versionCode == 123, "version code parsed");
        expect("0.2.0-preview.3".equals(manifest.versionName), "version name parsed");
        expect("downloads.urlget.cyou".equals(manifest.apkUrl.getHost()),
                "Cloudflare primary mirror parsed");
        expect("github.com".equals(manifest.apkFallbackUrl.getHost()),
                "GitHub fallback mirror parsed");
        expect(UpdatePolicy.isNewer(123, 122), "greater version is newer");
        expect(!UpdatePolicy.isNewer(123, 123), "equal version is not newer");
        expect(UpdatePolicy.shouldCheck(86_400_001L, 1L, false),
                "daily boundary elapsed");
        expect(!UpdatePolicy.shouldCheck(86_400_000L, 1L, false),
                "one millisecond remains");
        expect(UpdatePolicy.shouldCheck(2L, 1L, true), "manual bypasses throttle");
        expect(CERT.equals(UpdatePolicy.normalizeHex(CERT.toUpperCase())),
                "fingerprint normalization is stable");
        expect(UpdatePolicy.shouldResumePendingInstall(true, true, true),
                "persisted install resumes after Activity recreation");
        expect(!UpdatePolicy.shouldResumePendingInstall(false, true, true),
                "install does not resume without persisted user intent");
        expect(!UpdatePolicy.shouldResumePendingInstall(true, false, true),
                "install does not resume without verified APK");
        expect(!UpdatePolicy.shouldResumePendingInstall(true, true, false),
                "install waits until unknown-source permission is granted");
        expect(UpdatePolicy.isSameArtifact(manifest, UpdateManifest.parse(validJson())),
                "identical download artifact is accepted");
        UpdateManifest changedVersion = UpdateManifest.parse(validJson()
                .replace("\"versionCode\":123", "\"versionCode\":124")
                .replace("0.2.0-preview.3", "0.2.0-preview.4"));
        expect(!UpdatePolicy.isSameArtifact(changedVersion, manifest),
                "superseded download artifact is rejected");
        UpdateManifest changedFallback = UpdateManifest.parse(validJson().replace(
                "/v0.2.0-preview.3/DisplayWeave-Android.apk\",\"apkSize\"",
                "/v0.2.0-preview.4/DisplayWeave-Android.apk\",\"apkSize\""));
        expect(!UpdatePolicy.isSameArtifact(changedFallback, manifest),
                "changed fallback mirror is rejected");
        UpdateManifest legacySingleSource = UpdateManifest.parse(validJson().replace(
                "\"apkFallbackUrl\":\"https://github.com/chenyuhao0628/displayweave/"+
                        "releases/download/v0.2.0-preview.3/DisplayWeave-Android.apk\",", ""));
        expect(legacySingleSource.apkFallbackUrl == null,
                "legacy single-source manifest remains accepted");
        expect(UpdatePolicy.canInstall(manifest, manifest, 122),
                "verified newer artifact can install");
        expect(!UpdatePolicy.canInstall(manifest, manifest, 123),
                "equal installed version cannot reinstall through updater");

        expectThrows(() -> UpdateManifest.parse(validJson().replace(
                "https://downloads.urlget.cyou", "http://downloads.urlget.cyou")),
                "non-HTTPS APK URL rejected");
        expectThrows(() -> UpdateManifest.parse(validJson().replace(
                "https://downloads.urlget.cyou", "https://downloads.urlget.cyou.evil.example")),
                "mirror suffix attack rejected");
        expectThrows(() -> UpdateManifest.parse(validJson().replace(
                "https://github.com/chenyuhao0628", "https://github.com.evil.example/chenyuhao0628")),
                "fallback suffix attack rejected");
        expectThrows(() -> UpdateManifest.parse(validJson().replace(
                "https://downloads.urlget.cyou/releases/v0.2.0-preview.3/DisplayWeave-Android.apk",
                "https://downloads.urlget.cyou/releases/v0.2.0-preview.3/extra/DisplayWeave-Android.apk")),
                "nested mirror artifact path rejected");
        expectThrows(() -> UpdateManifest.parse(validJson().replace(
                "https://downloads.urlget.cyou/releases/v0.2.0-preview.3/DisplayWeave-Android.apk",
                "https://downloads.urlget.cyou/releases/v0.2.0-preview.3/DisplayWeave-Android.apk?bypass=1")),
                "mirror query rejected");
        expectThrows(() -> UpdateManifest.parse(validJson()
                        .replace("\"apkUrl\":\"https://downloads.urlget.cyou/releases/"+
                                        "v0.2.0-preview.3/DisplayWeave-Android.apk\"",
                                "\"apkUrl\":\"https://github.com/chenyuhao0628/displayweave/"+
                                        "releases/download/v0.2.0-preview.3/DisplayWeave-Android.apk\"")
                        .replace("\"apkFallbackUrl\":\"https://github.com/chenyuhao0628/"+
                                        "displayweave/releases/download/v0.2.0-preview.3/"+
                                        "DisplayWeave-Android.apk\"",
                                "\"apkFallbackUrl\":\"https://downloads.urlget.cyou/releases/"+
                                        "v0.2.0-preview.3/DisplayWeave-Android.apk\"")),
                "reversed mirror order rejected");
        expectThrows(() -> UpdateManifest.parse(validJson().replace(
                "app.opendisplay.android", "app.example.wrong")),
                "wrong package rejected");
        expectThrows(() -> UpdateManifest.parse(validJson().replace(HASH, "xyz")),
                "bad hash rejected");
        expectThrows(() -> UpdateManifest.parse(validJson().replace(
                CERT, "1111111111111111111111111111111111111111111111111111111111111111")),
                "unpinned signer fingerprint rejected");
        expectThrows(() -> UpdateManifest.parse(validJson().replace(
                "\"schemaVersion\":1", "\"schemaVersion\":2")),
                "unknown schema rejected");
        expectThrows(() -> UpdateManifest.parse(validJson().replace(
                "\"minimumSdk\":26", "\"minimumSdk\":25")),
                "unsupported SDK floor rejected");

        String androidManifest = Files.readString(Path.of("src/main/AndroidManifest.xml"));
        expect(androidManifest.contains("android.permission.REQUEST_INSTALL_PACKAGES"),
                "package-install permission declared");
        expect(androidManifest.contains("android:name=\".update.UpdateFileProvider\""),
                "update provider declared");
        expect(androidManifest.contains(
                        "android:authorities=\"app.opendisplay.android.update-files\""),
                "update provider authority fixed");
        expect(androidManifest.contains("android:exported=\"false\""),
                "update provider is not exported");
        expect(androidManifest.contains("android:grantUriPermissions=\"true\""),
                "update provider grants per-request reads");

        String updateClient = Files.readString(Path.of(
                "src/main/java/app/opendisplay/android/update/UpdateClient.java"));
        expect(updateClient.contains("setUseCaches(false)"),
                "manifest HTTP cache is disabled");
        expect(updateClient.contains("no-cache, no-store, max-age=0"),
                "manifest requests force cache revalidation");
        String coordinator = Files.readString(Path.of(
                "src/main/java/app/opendisplay/android/update/UpdateCoordinator.java"));
        expect(coordinator.contains("displayweave_cache_bust"),
                "manifest URL uses a cache-busting query");
        expect(coordinator.contains("正在确认更新仍为最新版本"),
                "install path rechecks the current manifest");
        expect(coordinator.contains("cleanupCompletedOrInvalidDownload"),
                "completed or invalid update files are cleaned on resume");
        expect(coordinator.contains("catch (UpdateClient.MirrorUnavailableException"),
                "only mirror availability errors trigger fallback");
        expect(coordinator.indexOf("downloadFromAvailableMirror")
                        < coordinator.indexOf("UpdateVerifier.verifyFile"),
                "all mirrors share one post-download verifier");
        String activity = Files.readString(Path.of(
                "src/main/java/app/opendisplay/android/MainActivity.java"));
        expect(activity.contains("progressBarStyleHorizontal"),
                "download UI contains a horizontal progress bar");
        expect(activity.contains("updateDownloadProgress.setProgress"),
                "download progress updates the visible bar");

        System.out.println("UpdatePolicySelfTest PASS");
    }

    private static String validJson() {
        return "{"+
                "\"schemaVersion\":1,"+
                "\"packageName\":\"app.opendisplay.android\","+
                "\"versionCode\":123,"+
                "\"versionName\":\"0.2.0-preview.3\","+
                "\"minimumSdk\":26,"+
                "\"apkUrl\":\"https://downloads.urlget.cyou/releases/"+
                "v0.2.0-preview.3/DisplayWeave-Android.apk\","+
                "\"apkFallbackUrl\":\"https://github.com/chenyuhao0628/displayweave/"+
                "releases/download/v0.2.0-preview.3/DisplayWeave-Android.apk\","+
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

package app.opendisplay.android.update;

import java.io.File;
import java.io.FileOutputStream;
import java.nio.charset.StandardCharsets;

public final class UpdateVerifierSelfTest {
    private static final byte[] FIXTURE =
            "DisplayWeave update fixture\n".getBytes(StandardCharsets.UTF_8);
    private static final String HASH =
            "299de81054c36e6008cafe41f54125adfb815097fb1838dd7c1194c6b9189ee1";
    private static final String CERT =
            "89805f045800ea18b56b84b32e8e31b1710a3c7bf3c85fda54d260d1fc6d589d";

    public static void main(String[] args) throws Exception {
        File directory = new File(System.getProperty("java.io.tmpdir"),
                "displayweave-update-verifier-" + System.nanoTime());
        expect(directory.mkdirs(), "temporary directory created");
        File fixture = new File(directory, "DisplayWeave-update.apk.part");

        write(fixture);
        expect(HASH.equals(UpdateVerifier.sha256(fixture)), "fixture hash is stable");
        UpdateVerifier.verifyFile(fixture, manifest(FIXTURE.length, HASH));
        expect(fixture.isFile(), "valid file is retained");

        expectThrowsAndDeleted(fixture, manifest(FIXTURE.length + 1L, HASH),
                "wrong-size file is deleted");
        write(fixture);
        expectThrowsAndDeleted(fixture, manifest(FIXTURE.length, HASH.replace('2', '3')),
                "wrong-hash file is deleted");

        expect(directory.delete(), "temporary directory removed");
        System.out.println("UpdateVerifierSelfTest PASS");
    }

    private static UpdateManifest manifest(long size, String hash) {
        return UpdateManifest.parse("{"+
                "\"schemaVersion\":1,"+
                "\"packageName\":\"app.opendisplay.android\","+
                "\"versionCode\":123,"+
                "\"versionName\":\"0.2.0-preview.3\","+
                "\"minimumSdk\":26,"+
                "\"apkUrl\":\"https://github.com/chenyuhao0628/displayweave/releases/"+
                "download/v0.2.0-preview.3/DisplayWeave-Android.apk\","+
                "\"apkSize\":"+size+","+
                "\"sha256\":\""+hash+"\","+
                "\"signingCertificateSha256\":\""+CERT+"\","+
                "\"publishedAt\":\"2026-07-14T00:00:00Z\","+
                "\"releaseNotesUrl\":\"https://github.com/chenyuhao0628/"+
                "displayweave/releases/tag/v0.2.0-preview.3\"}");
    }

    private static void write(File file) throws Exception {
        try (FileOutputStream output = new FileOutputStream(file)) {
            output.write(FIXTURE);
        }
    }

    private static void expectThrowsAndDeleted(
            File file, UpdateManifest manifest, String message) {
        try {
            UpdateVerifier.verifyFile(file, manifest);
            throw new AssertionError(message);
        } catch (IllegalArgumentException expected) {
            expect(!file.exists(), message);
        }
    }

    private static void expect(boolean condition, String message) {
        if (!condition) throw new AssertionError(message);
    }
}

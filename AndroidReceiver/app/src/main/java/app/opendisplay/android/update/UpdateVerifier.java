package app.opendisplay.android.update;

import android.content.Context;
import android.content.pm.PackageInfo;
import android.content.pm.PackageManager;
import android.content.pm.Signature;
import android.os.Build;

import java.io.File;
import java.io.FileInputStream;
import java.io.IOException;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.util.Locale;

public final class UpdateVerifier {
    private UpdateVerifier() {}

    public static String sha256(File file) throws IOException {
        MessageDigest digest = digest();
        try (FileInputStream input = new FileInputStream(file)) {
            byte[] buffer = new byte[16 * 1024];
            int count;
            while ((count = input.read(buffer)) != -1) digest.update(buffer, 0, count);
        }
        return hexadecimal(digest.digest());
    }

    public static void verifyFile(File file, UpdateManifest manifest) {
        try {
            require(file.isFile(), "Downloaded APK is missing");
            require(file.length() == manifest.apkSize, "Downloaded APK size mismatch");
            byte[] actual = hexadecimalBytes(sha256(file));
            byte[] expected = hexadecimalBytes(manifest.sha256);
            require(MessageDigest.isEqual(actual, expected), "Downloaded APK hash mismatch");
        } catch (IOException | IllegalArgumentException error) {
            deleteFailed(file);
            if (error instanceof IllegalArgumentException) {
                throw (IllegalArgumentException) error;
            }
            throw new IllegalArgumentException("Unable to verify downloaded APK", error);
        }
    }

    @SuppressWarnings("deprecation")
    public static void verifyPackage(Context context, File file, UpdateManifest manifest) {
        try {
            PackageManager manager = context.getPackageManager();
            int flags = Build.VERSION.SDK_INT >= 28
                    ? PackageManager.GET_SIGNING_CERTIFICATES
                    : PackageManager.GET_SIGNATURES;
            PackageInfo info = manager.getPackageArchiveInfo(file.getAbsolutePath(), flags);
            require(info != null, "Downloaded file is not an APK");
            require(UpdateManifest.EXPECTED_PACKAGE_NAME.equals(info.packageName),
                    "Downloaded APK package mismatch");
            long versionCode = Build.VERSION.SDK_INT >= 28
                    ? info.getLongVersionCode()
                    : info.versionCode;
            require(versionCode == manifest.versionCode, "Downloaded APK version mismatch");
            require(manifest.minimumSdk <= Build.VERSION.SDK_INT,
                    "Downloaded APK requires a newer Android version");
            if (info.applicationInfo != null && Build.VERSION.SDK_INT >= 24) {
                require(info.applicationInfo.minSdkVersion == manifest.minimumSdk,
                        "Downloaded APK minimum SDK mismatch");
            }

            Signature[] signatures;
            if (Build.VERSION.SDK_INT >= 28) {
                require(info.signingInfo != null, "Downloaded APK has no signing information");
                signatures = info.signingInfo.getApkContentsSigners();
            } else {
                signatures = info.signatures;
            }
            require(signatures != null && signatures.length == 1,
                    "Downloaded APK must have exactly one signer");
            String fingerprint = hexadecimal(digest().digest(signatures[0].toByteArray()));
            require(MessageDigest.isEqual(
                            hexadecimalBytes(fingerprint),
                            hexadecimalBytes(manifest.signingCertificateSha256)),
                    "Downloaded APK signer mismatch");
        } catch (IllegalArgumentException error) {
            deleteFailed(file);
            throw error;
        }
    }

    @SuppressWarnings("deprecation")
    public static long packageVersionCode(Context context, File file) {
        PackageInfo info = context.getPackageManager().getPackageArchiveInfo(
                file.getAbsolutePath(), 0);
        require(info != null, "Downloaded file is not an APK");
        require(UpdateManifest.EXPECTED_PACKAGE_NAME.equals(info.packageName),
                "Downloaded APK package mismatch");
        return Build.VERSION.SDK_INT >= 28 ? info.getLongVersionCode() : info.versionCode;
    }

    private static MessageDigest digest() {
        try {
            return MessageDigest.getInstance("SHA-256");
        } catch (NoSuchAlgorithmException impossible) {
            throw new IllegalStateException("SHA-256 unavailable", impossible);
        }
    }

    private static byte[] hexadecimalBytes(String value) {
        String normalized = UpdatePolicy.normalizeHex(value);
        byte[] result = new byte[normalized.length() / 2];
        for (int index = 0; index < result.length; index++) {
            result[index] = (byte) Integer.parseInt(normalized.substring(index * 2, index * 2 + 2), 16);
        }
        return result;
    }

    private static String hexadecimal(byte[] value) {
        StringBuilder result = new StringBuilder(value.length * 2);
        for (byte item : value) result.append(String.format(Locale.ROOT, "%02x", item & 0xff));
        return result.toString();
    }

    private static void require(boolean condition, String message) {
        if (!condition) throw new IllegalArgumentException(message);
    }

    private static void deleteFailed(File file) {
        if (file.exists() && !file.delete()) file.deleteOnExit();
    }
}

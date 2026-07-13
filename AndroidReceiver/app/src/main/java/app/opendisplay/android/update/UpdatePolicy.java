package app.opendisplay.android.update;

import java.util.Locale;

public final class UpdatePolicy {
    public static final long CHECK_INTERVAL_MILLIS = 24L * 60L * 60L * 1_000L;

    private UpdatePolicy() {}

    public static boolean isNewer(long remoteVersionCode, long installedVersionCode) {
        return remoteVersionCode > installedVersionCode;
    }

    public static boolean shouldCheck(long nowMillis, long lastCheckMillis, boolean manual) {
        if (manual || lastCheckMillis <= 0L) {
            return true;
        }
        return nowMillis - lastCheckMillis >= CHECK_INTERVAL_MILLIS;
    }

    public static boolean shouldResumePendingInstall(
            boolean persistedUserIntent, boolean verifiedFileExists, boolean canInstall) {
        return persistedUserIntent && verifiedFileExists && canInstall;
    }

    public static String normalizeHex(String value) {
        if (value == null) {
            throw new IllegalArgumentException("Missing hexadecimal value");
        }
        String normalized = value.replace(":", "")
                .replaceAll("\\s", "")
                .toLowerCase(Locale.ROOT);
        if (!normalized.matches("[0-9a-f]{64}")) {
            throw new IllegalArgumentException("Expected a SHA-256 hexadecimal value");
        }
        return normalized;
    }
}

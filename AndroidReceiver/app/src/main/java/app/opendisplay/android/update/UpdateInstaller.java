package app.opendisplay.android.update;

import android.app.Activity;
import android.content.Intent;
import android.net.Uri;
import android.os.Build;
import android.provider.Settings;

public final class UpdateInstaller {
    private UpdateInstaller() {}

    public static boolean canInstall(Activity activity) {
        return Build.VERSION.SDK_INT < 26
                || activity.getPackageManager().canRequestPackageInstalls();
    }

    /** Returns true when Package Installer launched, false when permission settings launched. */
    public static boolean install(Activity activity) {
        if (!canInstall(activity)) {
            Intent permission = new Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                    Uri.parse("package:" + activity.getPackageName()));
            activity.startActivity(permission);
            return false;
        }
        Intent install = new Intent(Intent.ACTION_INSTALL_PACKAGE, UpdateFileProvider.uri());
        install.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION);
        activity.startActivity(install);
        return true;
    }
}

package app.opendisplay.android.update;

import android.app.Activity;
import android.content.SharedPreferences;
import android.content.pm.PackageInfo;
import android.os.Handler;
import android.os.Looper;

import java.io.File;
import java.net.URL;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

public final class UpdateCoordinator {
    private static final String FEED_URL =
            "https://chenyuhao0628.github.io/displayweave/android-update.json";
    private static final String KEY_LAST_SUCCESSFUL_CHECK = "updateLastSuccessfulCheck";

    public interface Listener {
        void onCheckState(String state);
        void onUpdateAvailable(UpdateManifest manifest);
        void onDownloadProgress(int percent);
        void onVerifiedUpdateReady(UpdateManifest manifest);
        void onUpdateError(String message, boolean manual);
    }

    private final Activity activity;
    private final SharedPreferences preferences;
    private final Listener listener;
    private final UpdateClient client = new UpdateClient();
    private final ExecutorService executor = Executors.newSingleThreadExecutor();
    private final Handler main = new Handler(Looper.getMainLooper());
    private boolean checking;
    private UpdateManifest pendingManifest;
    private File pendingFile;
    private boolean waitingForInstallPermission;

    public UpdateCoordinator(
            Activity activity, SharedPreferences preferences, Listener listener) {
        this.activity = activity;
        this.preferences = preferences;
        this.listener = listener;
    }

    public synchronized void check(boolean manual) {
        long now = System.currentTimeMillis();
        long last = preferences.getLong(KEY_LAST_SUCCESSFUL_CHECK, 0L);
        if (checking || !UpdatePolicy.shouldCheck(now, last, manual)) return;
        checking = true;
        post(() -> listener.onCheckState("正在检查更新…"));
        executor.execute(() -> {
            try {
                UpdateManifest manifest = client.fetchManifest(new URL(FEED_URL));
                long installed = installedVersionCode();
                preferences.edit().putLong(KEY_LAST_SUCCESSFUL_CHECK,
                        System.currentTimeMillis()).apply();
                if (UpdatePolicy.isNewer(manifest.versionCode, installed)) {
                    post(() -> listener.onUpdateAvailable(manifest));
                } else {
                    post(() -> listener.onCheckState("已是最新版本"));
                }
            } catch (Exception error) {
                post(() -> listener.onUpdateError(readable(error), manual));
            } finally {
                synchronized (UpdateCoordinator.this) { checking = false; }
            }
        });
    }

    public void download(UpdateManifest manifest) {
        post(() -> listener.onCheckState("正在下载 " + manifest.versionName + "…"));
        executor.execute(() -> {
            File directory;
            try {
                directory = UpdateFileProvider.updateDirectory(activity);
            } catch (RuntimeException error) {
                post(() -> listener.onUpdateError(readable(error), true));
                return;
            }
            File temporary = new File(directory, "DisplayWeave-update.apk.part");
            File verified = new File(directory, UpdateFileProvider.FILE_NAME);
            try {
                if (verified.exists() && !verified.delete()) {
                    throw new IllegalStateException("无法替换旧的更新文件");
                }
                client.download(manifest.apkUrl.toURL(), temporary, manifest.apkSize,
                        (downloaded, total) -> post(() -> listener.onDownloadProgress(
                                (int) Math.min(100L, downloaded * 100L / Math.max(1L, total)))));
                UpdateVerifier.verifyFile(temporary, manifest);
                UpdateVerifier.verifyPackage(activity, temporary, manifest);
                if (!temporary.renameTo(verified)) {
                    throw new IllegalStateException("无法保存已验证的更新文件");
                }
                pendingManifest = manifest;
                pendingFile = verified;
                post(() -> listener.onVerifiedUpdateReady(manifest));
            } catch (Exception error) {
                if (temporary.exists()) temporary.delete();
                if (verified.exists()) verified.delete();
                post(() -> listener.onUpdateError(readable(error), true));
            }
        });
    }

    public void installPending() {
        if (pendingManifest == null || pendingFile == null || !pendingFile.isFile()) {
            listener.onUpdateError("已验证的更新文件不存在，请重新下载", true);
            return;
        }
        waitingForInstallPermission = !UpdateInstaller.install(activity);
    }

    public void resumePendingInstall() {
        if (waitingForInstallPermission && UpdateInstaller.canInstall(activity)) {
            waitingForInstallPermission = false;
            UpdateInstaller.install(activity);
        }
    }

    public void shutdown() {
        executor.shutdownNow();
    }

    private long installedVersionCode() throws Exception {
        PackageInfo info = activity.getPackageManager().getPackageInfo(activity.getPackageName(), 0);
        return android.os.Build.VERSION.SDK_INT >= 28 ? info.getLongVersionCode() : info.versionCode;
    }

    private void post(Runnable action) {
        main.post(action);
    }

    private static String readable(Exception error) {
        String message = error.getMessage();
        return message == null || message.isBlank()
                ? error.getClass().getSimpleName() : message;
    }
}

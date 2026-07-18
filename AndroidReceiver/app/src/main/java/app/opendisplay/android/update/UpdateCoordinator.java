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
    private static final String KEY_PENDING_INSTALL_PERMISSION = "updatePendingInstallPermission";

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
    private boolean downloading;
    private boolean installing;
    private UpdateManifest pendingManifest;
    private File pendingFile;

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
                UpdateManifest manifest = client.fetchManifest(freshManifestUrl());
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

    public synchronized void download(UpdateManifest manifest) {
        if (downloading) return;
        downloading = true;
        post(() -> listener.onCheckState("正在下载 " + manifest.versionName + "…"));
        executor.execute(() -> {
            File directory;
            try {
                directory = UpdateFileProvider.updateDirectory(activity);
            } catch (RuntimeException error) {
                post(() -> listener.onUpdateError(readable(error), true));
                synchronized (UpdateCoordinator.this) { downloading = false; }
                return;
            }
            File temporary = new File(directory, "DisplayWeave-update.apk.part");
            File verified = new File(directory, UpdateFileProvider.FILE_NAME);
            try {
                preferences.edit().remove(KEY_PENDING_INSTALL_PERMISSION).apply();
                pendingManifest = null;
                pendingFile = null;
                if (temporary.exists() && !temporary.delete()) {
                    throw new IllegalStateException("无法清理未完成的更新文件");
                }
                if (verified.exists() && !verified.delete()) {
                    throw new IllegalStateException("无法替换旧的更新文件");
                }
                downloadFromAvailableMirror(manifest, temporary);
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
            } finally {
                synchronized (UpdateCoordinator.this) { downloading = false; }
            }
        });
    }

    private void downloadFromAvailableMirror(UpdateManifest manifest, File temporary)
            throws Exception {
        UpdateClient.Progress progress = (downloaded, total) -> post(() ->
                listener.onDownloadProgress((int) Math.min(
                        100L, downloaded * 100L / Math.max(1L, total))));
        try {
            client.download(manifest.apkUrl.toURL(), temporary, manifest.apkSize, progress);
        } catch (UpdateClient.MirrorUnavailableException primaryError) {
            if (manifest.apkFallbackUrl == null) throw primaryError;
            post(() -> listener.onCheckState("主下载源不可用，正在切换备用源…"));
            post(() -> listener.onDownloadProgress(0));
            try {
                client.download(
                        manifest.apkFallbackUrl.toURL(), temporary, manifest.apkSize, progress);
            } catch (Exception fallbackError) {
                fallbackError.addSuppressed(primaryError);
                throw fallbackError;
            }
        }
    }

    public void installPending() {
        UpdateManifest manifest = pendingManifest;
        File file = pendingFile;
        if (manifest == null || file == null || !file.isFile()) {
            listener.onUpdateError("已验证的更新文件不存在，请重新下载", true);
            return;
        }
        validateLatestAndInstall(manifest, file);
    }

    public void resumePendingInstall() {
        boolean persisted = preferences.getBoolean(KEY_PENDING_INSTALL_PERMISSION, false);
        File verified;
        try {
            verified = new File(
                    UpdateFileProvider.updateDirectory(activity), UpdateFileProvider.FILE_NAME);
        } catch (RuntimeException unavailableStorage) {
            if (persisted) {
                preferences.edit().remove(KEY_PENDING_INSTALL_PERMISSION).apply();
            }
            return;
        }
        cleanupCompletedOrInvalidDownload(verified);
        if (persisted && !verified.isFile()) {
            preferences.edit().remove(KEY_PENDING_INSTALL_PERMISSION).apply();
            return;
        }
        if (UpdatePolicy.shouldResumePendingInstall(
                persisted, verified.isFile(), UpdateInstaller.canInstall(activity))) {
            validateLatestAndInstall(null, verified);
        }
    }

    public void shutdown() {
        executor.shutdownNow();
    }

    private long installedVersionCode() throws Exception {
        PackageInfo info = activity.getPackageManager().getPackageInfo(activity.getPackageName(), 0);
        return android.os.Build.VERSION.SDK_INT >= 28 ? info.getLongVersionCode() : info.versionCode;
    }

    private URL freshManifestUrl() throws Exception {
        return new URL(FEED_URL + "?displayweave_cache_bust=" + System.currentTimeMillis());
    }

    private synchronized void validateLatestAndInstall(
            UpdateManifest expectedManifest, File verified) {
        if (installing) return;
        installing = true;
        post(() -> listener.onCheckState("正在确认更新仍为最新版本…"));
        executor.execute(() -> {
            boolean installPosted = false;
            try {
                UpdateManifest latest = client.fetchManifest(freshManifestUrl());
                if (expectedManifest != null
                        && !UpdatePolicy.isSameArtifact(latest, expectedManifest)) {
                    deleteVerifiedDownload(verified);
                    throw new IllegalStateException("更新版本已变化，请重新下载最新版本");
                }
                UpdateVerifier.verifyFile(verified, latest);
                UpdateVerifier.verifyPackage(activity, verified, latest);
                long installed = installedVersionCode();
                if (!UpdatePolicy.canInstall(latest, latest, installed)) {
                    deleteVerifiedDownload(verified);
                    throw new IllegalStateException("下载的更新已不是比当前安装版本更新的版本");
                }
                pendingManifest = latest;
                pendingFile = verified;
                post(() -> {
                    try {
                        boolean launched = UpdateInstaller.install(activity);
                        preferences.edit().putBoolean(
                                KEY_PENDING_INSTALL_PERMISSION, !launched).apply();
                        listener.onCheckState(launched
                                ? "已打开系统安装界面"
                                : "请允许安装未知应用后返回");
                    } finally {
                        synchronized (UpdateCoordinator.this) { installing = false; }
                    }
                });
                installPosted = true;
            } catch (Exception error) {
                post(() -> listener.onUpdateError(readable(error), true));
            } finally {
                if (!installPosted) {
                    synchronized (UpdateCoordinator.this) { installing = false; }
                }
            }
        });
    }

    private void cleanupCompletedOrInvalidDownload(File verified) {
        File temporary = new File(verified.getParentFile(), "DisplayWeave-update.apk.part");
        if (temporary.exists()) temporary.delete();
        if (!verified.isFile()) return;
        try {
            if (UpdateVerifier.packageVersionCode(activity, verified) <= installedVersionCode()) {
                deleteVerifiedDownload(verified);
            }
        } catch (Exception invalidPackage) {
            deleteVerifiedDownload(verified);
        }
    }

    private synchronized void deleteVerifiedDownload(File verified) {
        if (verified.exists()) verified.delete();
        if (verified.equals(pendingFile)) {
            pendingFile = null;
            pendingManifest = null;
        }
        preferences.edit().remove(KEY_PENDING_INSTALL_PERMISSION).apply();
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

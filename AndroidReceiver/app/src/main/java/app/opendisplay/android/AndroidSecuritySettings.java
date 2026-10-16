package app.opendisplay.android;

import android.app.Activity;
import android.app.AlertDialog;
import android.content.ClipData;
import android.content.ClipboardManager;
import android.content.Context;
import android.os.Handler;
import android.os.Looper;
import android.os.PersistableBundle;
import android.widget.Button;
import android.widget.CheckBox;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;
import java.util.function.Consumer;

/** Local, explicit pairing controls. Invitations never enter preferences or logs. */
final class AndroidSecuritySettings {
    private static final String PREFS = "OpenDisplayAndroid";
    private static final String LEGACY = "insecureLegacyReceiver";
    private final Activity activity;
    private final ReceiverUi ui;
    private final Runnable stop, start, cancelPending;
    private final Consumer<String> revoke;
    private final Handler handler = new Handler(Looper.getMainLooper());
    private AlertDialog settings, invitationDialog, confirmation;
    private String copiedInvitation;

    AndroidSecuritySettings(Activity activity, Runnable stop, Runnable start,
                            Runnable cancelPending, Consumer<String> revoke) {
        this.activity = activity; ui = new ReceiverUi(activity);
        this.stop = stop; this.start = start; this.cancelPending = cancelPending; this.revoke = revoke;
    }
    static boolean legacyEnabled(Context context) {
        return context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getBoolean(LEGACY, false);
    }
    private LinearLayout column() {
        LinearLayout view = new LinearLayout(activity);
        view.setOrientation(LinearLayout.VERTICAL);
        view.setPadding(ui.dp(20), ui.dp(12), ui.dp(20), ui.dp(12));
        return view;
    }
    private void add(LinearLayout parent, String text) {
        TextView view = ui.text(text, 14, ui.primary, false);
        view.setPadding(0, ui.dp(8), 0, ui.dp(8));
        parent.addView(view);
    }
    private void action(LinearLayout parent, String label, Runnable action) {
        Button button = ui.button(label);
        button.setOnClickListener(ignored -> action.run()); parent.addView(button);
    }
    private void error(Exception error) {
        android.util.Log.w("DisplayWeave", "Local security settings operation failed", error);
        String detail = error.getMessage();
        if (detail == null || detail.isEmpty()) detail = error.getClass().getSimpleName();
        confirmation = new AlertDialog.Builder(activity).setTitle("安全状态不可用")
                .setMessage("请解锁设备后重新载入安全状态；密钥丢失或证书过期时，显式重置身份并重新配对。\n\n"
                        + detail).setPositiveButton("知道了", null).show();
    }
    void showConnectionModes() {
        String[] modes = {"DisplayWeave 加密配对", "OpenDisplay 兼容（未加密）"};
        confirmation = new AlertDialog.Builder(activity).setTitle("连接客户端")
                .setSingleChoiceItems(modes, legacyEnabled(activity) ? 1 : 0, (dialog, which) -> {
                    dialog.dismiss();
                    if ((which == 1) == legacyEnabled(activity)) return;
                    if (which == 0) { changeLegacy(false); return; }
                    confirmLegacy();
                }).setNegativeButton("取消", null).show();
    }
    private void confirmLegacy() {
        confirmation = new AlertDialog.Builder(activity).setTitle("使用 OpenDisplay 兼容连接？")
                .setMessage("无需配对邀请，画面和输入未加密。请使用可信网络；更改模式会断开当前连接。")
                .setNegativeButton("取消", null)
                .setPositiveButton("启用明文兼容", (dialog, which) -> changeLegacy(true)).show();
    }
    void show() {
        if (settings != null) settings.dismiss();
        LinearLayout content = column();
        add(content, legacyEnabled(activity) ? "当前：旧版明文兼容。画面和输入未加密。" : "当前：加密接收。只有通过配对认证的 Mac 才能连接。");
        add(content, "第一次连接：生成邀请，通过可信渠道复制到 Mac 的“安全与配对”设置，再从设备列表连接。邀请两分钟内有效，仅限一个新设备。");
        try {
            AndroidSecurityStore store = AndroidSecurityStore.get(activity);
            add(content, "本机证书指纹\n" + store.pairing.localFingerprint);
            if (!legacyEnabled(activity)) action(content, "生成接收邀请", () -> invite(store));
            for (SecurePairingState.Peer peer : store.pairing.peers()) {
                add(content, (peer.revoked ? "已撤销：" : "已信任：") + peer.name + "\n" + peer.installID + "\n" + peer.certificateSHA256);
                if (!peer.revoked) action(content, "撤销 “" + peer.name + "”", () -> {
                    try { store.pairing.revoke(peer.installID); revoke.accept(peer.installID); show(); }
                    catch (Exception failure) { error(failure); }
                });
            }
        } catch (Exception failure) { add(content, "无法读取安全身份：" + failure.getMessage()); }
        action(content, "重新载入安全状态", () -> {
            stop.run();
            try { AndroidSecurityStore.reload(activity); start.run(); show(); }
            catch (Exception failure) { error(failure); }
        });
        action(content, "重置本机传输身份…", () -> {
            confirmation = new AlertDialog.Builder(activity).setTitle("重置传输身份？")
                    .setMessage("将断开连接并生成新的传输密钥。撤销记录会保留；请在对端撤销旧配对并获取新邀请。应用签名和更新签名不受影响。")
                    .setNegativeButton("取消", null).setPositiveButton("重置并重新配对", (dialog, which) -> {
                        stop.run();
                        try { AndroidSecurityStore.resetIdentity(activity); start.run(); show(); }
                        catch (Exception failure) { error(failure); }
                    }).show();
        });
        CheckBox legacy = new CheckBox(activity);
        legacy.setText("允许旧版明文接收（不安全）"); legacy.setChecked(legacyEnabled(activity));
        legacy.setOnCheckedChangeListener((button, enabled) -> {
            if (!enabled) { if (legacyEnabled(activity)) changeLegacy(false); return; }
            legacy.setChecked(false);
            confirmation = new AlertDialog.Builder(activity).setTitle("允许未认证、未加密的连接？")
                    .setMessage("仅供旧版应用在可信网络连接。启用后当前连接断开，关闭配对监听；不会在 TLS 失败时自动启用。")
                    .setNegativeButton("取消", null).setPositiveButton("启用明文兼容", (dialog, which) -> changeLegacy(true)).show();
        });
        content.addView(legacy);
        ScrollView scroll = new ScrollView(activity); scroll.addView(content);
        settings = new AlertDialog.Builder(activity).setTitle("安全与配对").setView(scroll)
                .setPositiveButton("完成", null).show();
    }
    private void changeLegacy(boolean enabled) {
        cancelInvitation();
        stop.run();
        activity.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().putBoolean(LEGACY, enabled).apply();
        start.run(); show();
    }
    private void invite(AndroidSecurityStore store) {
        cancelInvitation();
        try {
            String invitation = store.pairing.startPairing().encode();
            LinearLayout content = column();
            add(content, "两分钟内有效；使用一次即失效。关闭此窗口会取消邀请。不要公开此内容。");
            TextView value = ui.text(invitation, 13, ui.primary, false);
            // Use the owned copy button so clipboard cleanup remains bounded.
            content.addView(value);
            action(content, "复制邀请", () -> {
                ClipboardManager clipboard = activity.getSystemService(ClipboardManager.class);
                ClipData clip = ClipData.newPlainText("DisplayWeave pairing", invitation);
                PersistableBundle extras = new PersistableBundle();
                extras.putBoolean("android.content.extra.IS_SENSITIVE", true);
                clip.getDescription().setExtras(extras);
                clipboard.setPrimaryClip(clip); copiedInvitation = invitation;
            });
            ScrollView scroll = new ScrollView(activity); scroll.addView(content);
            invitationDialog = new AlertDialog.Builder(activity).setTitle("接收配对邀请").setView(scroll)
                    .setNegativeButton("关闭邀请", null).create();
            invitationDialog.setOnDismissListener(ignored -> cancelInvitation());
            invitationDialog.show();
            handler.postDelayed(new Runnable() {
                public void run() {
                    if (invitationDialog == null) return;
                    if (!store.pairing.pairingOpen()) {
                        cancelInvitation(); show(); return;
                    }
                    handler.postDelayed(this, 500);
                }
            }, 500);
        } catch (Exception failure) { error(failure); }
    }
    private void cancelInvitation() {
        handler.removeCallbacksAndMessages(null);
        AndroidSecurityStore.stopPairingIfLoaded(); cancelPending.run();
        AlertDialog old = invitationDialog; invitationDialog = null;
        if (old != null) { old.setOnDismissListener(null); old.dismiss(); }
        if (copiedInvitation != null) {
            ClipboardManager clipboard = activity.getSystemService(ClipboardManager.class);
            ClipData clip = clipboard.getPrimaryClip();
            if (clip != null && clip.getItemCount() == 1
                    && copiedInvitation.contentEquals(String.valueOf(clip.getItemAt(0).getText()))) {
                if (android.os.Build.VERSION.SDK_INT >= 28) clipboard.clearPrimaryClip();
                else clipboard.setPrimaryClip(ClipData.newPlainText("", ""));
            }
            copiedInvitation = null;
        }
    }
    void dismiss() {
        cancelInvitation();
        if (settings != null) { settings.dismiss(); settings = null; }
        if (confirmation != null) { confirmation.dismiss(); confirmation = null; }
    }
}

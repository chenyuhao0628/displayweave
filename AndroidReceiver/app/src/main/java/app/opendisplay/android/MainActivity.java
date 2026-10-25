package app.opendisplay.android;

import android.Manifest;
import android.app.AlertDialog;
import android.app.Activity;
import android.content.SharedPreferences;
import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.content.pm.PackageManager;
import android.graphics.Color;
import android.graphics.Rect;
import android.net.wifi.WifiManager;
import android.os.Build;
import android.os.Bundle;
import android.util.DisplayMetrics;
import android.view.Gravity;
import android.view.Display;
import android.view.MotionEvent;
import android.view.SurfaceHolder;
import android.view.SurfaceView;
import android.view.View;
import android.view.Window;
import android.view.WindowManager;
import android.widget.Button;
import android.widget.CheckBox;
import android.widget.ImageView;
import android.widget.FrameLayout;
import android.widget.LinearLayout;
import android.widget.ProgressBar;
import android.widget.ScrollView;
import android.widget.TextView;

import app.opendisplay.android.update.UpdateCoordinator;
import app.opendisplay.android.update.UpdateManifest;

import java.util.Locale;

public final class MainActivity extends Activity implements OpenDisplayServer.Listener {
    private static final int REQUEST_NEARBY_WIFI = 20;
    private static final String PREFS = "OpenDisplayAndroid";
    private static final String KEY_ONBOARDING_DISMISSED = "onboardingDismissed";
    private static final String KEY_KEEP_AWAKE = "keepAwake";
    private static final String KEY_SHOW_STATUS = "showStatusOverlay";
    private static final String KEY_SHOW_METRICS = "showMetrics";
    private static final String KEY_DISPLAY_PROFILE = "displayProfile";
    private static final String KEY_DECODER_LOW_LATENCY = "decoderLowLatency";
    private static final String KEY_WIFI_LOW_LATENCY = "wifiLowLatency";

    private ReceiverUi ui;
    private AndroidSecuritySettings securitySettings;
    private Button streamSettingsButton;
    private FrameLayout root;
    private ReceiverSurfaceView surfaceView;
    private CursorOverlayView cursorOverlay;
    private TextView statusView;
    private TextView idleStatusView;
    private Button connectionModeButton;
    private View idlePanel;
    private OpenDisplayServer server;
    private SurfaceHolder activeSurface;
    private ReceiverLifecycleCoordinator receiverLifecycle;
    private SharedPreferences prefs;
    private UpdateCoordinator updateCoordinator;
    private AlertDialog updateDownloadDialog;
    private ProgressBar updateDownloadProgress;
    private TextView updateDownloadProgressText;
    private String updateState = "尚未检查更新";
    private String currentStatus = "等待启动…";
    private boolean streaming;
    private boolean foreground;
    private String currentTransport = "unknown";
    private final ScrollGestureTracker scrollGesture = new ScrollGestureTracker();
    private TouchGestureCoordinator touchGesture;
    private Runnable pendingTouchHold;
    private StreamMetrics lastMetrics = new StreamMetrics(0, 0, 0, 0);
    private VideoStreamConfig lastStreamConfig = VideoStreamConfig.DEFAULT;
    private volatile float requestedSurfaceRefreshRate = 60f;
    private volatile String surfaceFrameRateStatus = "notRequested";
    private WifiLowLatencyLifecycle wifiLowLatencyLifecycle;
    private SurfaceFrameRateLifecycle surfaceFrameRateLifecycle;

    @Override
    @SuppressWarnings("deprecation")
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        ui = new ReceiverUi(this);
        requestWindowFeature(Window.FEATURE_NO_TITLE);
        getWindow().setFlags(WindowManager.LayoutParams.FLAG_FULLSCREEN,
                WindowManager.LayoutParams.FLAG_FULLSCREEN);
        if (Build.VERSION.SDK_INT >= 33
                && checkSelfPermission(Manifest.permission.NEARBY_WIFI_DEVICES)
                != PackageManager.PERMISSION_GRANTED) {
            requestPermissions(new String[] {Manifest.permission.NEARBY_WIFI_DEVICES}, REQUEST_NEARBY_WIFI);
        }
        prefs = getSharedPreferences(PREFS, MODE_PRIVATE);
        updateCoordinator = createUpdateCoordinator();
        wifiLowLatencyLifecycle = new WifiLowLatencyLifecycle(
                Build.VERSION.SDK_INT, createWifiLowLatencyLock());
        surfaceFrameRateLifecycle = new SurfaceFrameRateLifecycle(
                new SurfaceFrameRateLifecycle.Actions() {
                    @Override
                    public void apply(int fps, String reason) {
                        applyStreamRefreshRate(fps, reason);
                    }

                    @Override
                    public void clear(String reason) {
                        clearStreamRefreshRate(reason);
                    }
                });
        receiverLifecycle = new ReceiverLifecycleCoordinator(
                new ReceiverLifecycleCoordinator.Actions() {
                    @Override
                    public boolean start() {
                        return startServerIfReady();
                    }

                    @Override
                    public void stop() {
                        stopServer();
                    }
                });
        securitySettings = new AndroidSecuritySettings(this, receiverLifecycle::stopForSettings,
                () -> { receiverLifecycle.reevaluate(); refreshConnectionModeUi(); },
                () -> { if (server != null) server.cancelPendingAdmissions(); },
                id -> { if (server != null) server.revokePeer(id); });
        buildUi();
        applyKeepAwakePreference();
        showOnboardingIfNeeded();
    }

    @Override
    protected void onResume() {
        super.onResume();
        foreground = true;
        surfaceFrameRateLifecycle.onResume();
        updateWifiLowLatencyState();
        receiverLifecycle.onResume();
        updateCoordinator.resumePendingInstall();
        updateCoordinator.check(false);
    }

    @Override
    protected void onPause() {
        cancelTouchGesture();
        foreground = false;
        securitySettings.dismiss();
        updateWifiLowLatencyState();
        surfaceFrameRateLifecycle.onPause();
        receiverLifecycle.onPause();
        super.onPause();
    }

    @Override
    protected void onDestroy() {
        surfaceFrameRateLifecycle.onDestroy();
        wifiLowLatencyLifecycle.shutdown("activityDestroyed");
        updateCoordinator.shutdown();
        receiverLifecycle.onDestroy();
        super.onDestroy();
    }

    @Override
    public void onStatus(String status) {
        runOnUiThread(() -> setStatus(status));
    }

    @Override
    public void onConnected(boolean connected) {
        runOnUiThread(() -> {
            setStatus(connected ? "Mac 已连接，等待画面…" : "等待 Mac 连接…");
            if (!connected) {
                setStreaming(false);
                cursorOverlay.resetCursor();
            }
        });
    }

    @Override
    public void onStreaming(boolean streaming) {
        runOnUiThread(() -> setStreaming(streaming));
    }

    @Override
    public void onConnectionState(ReceiverConnectionStateSnapshot state) {
        runOnUiThread(() -> {
            switch (state.state) {
                case DISCONNECTED:
                    setStatus("等待 Mac 连接…");
                    break;
                case SOCKET_CONNECTED:
                case HELLO_SENT:
                case HELLO_ACCEPTED:
                    setStatus("正在连接…");
                    break;
                case STREAM_CONFIG_RECEIVED:
                case STREAM_CONFIG_ACCEPTED:
                    setStatus("正在协商视频配置…");
                    break;
                case DECODER_CONFIGURING:
                    surfaceFrameRateLifecycle.onDecoderRebuild();
                    setStatus("正在配置解码器…");
                    break;
                case DECODER_READY:
                    setStatus("正在配置解码器…");
                    break;
                case WAITING_FIRST_FRAME:
                    setStatus("等待首帧…");
                    break;
                case STREAMING:
                    setStatus("正在接收");
                    break;
                case RECOVERING:
                    setStatus("正在恢复画面…");
                    break;
                case FAILED:
                    setStatus("连接异常：" + state.reason);
                    break;
            }
            android.util.Log.i("DisplayWeave", "connectionState=" + state.state
                    + " reason=" + state.reason
                    + " generation=" + state.generation
                    + " sessionEpoch=" + state.sessionEpoch
                    + " configVersion=" + state.configVersion
                    + " enteredAtMs=" + state.enteredAtMs);
        });
    }

    @Override
    public void onCursor(double x, double y, boolean visible) {
        runOnUiThread(() -> cursorOverlay.moveCursor(x, y, visible));
    }

    @Override
    public void onCursorImage(byte[] png, double anchorX, double anchorY,
                              double normalizedWidth, double normalizedHeight) {
        if (png == null || png.length == 0 || png.length > CursorImagePolicy.MAX_BYTES) return;
        BitmapFactory.Options bounds = new BitmapFactory.Options();
        bounds.inJustDecodeBounds = true;
        BitmapFactory.decodeByteArray(png, 0, png.length, bounds);
        if (!CursorImagePolicy.accepts(png.length, bounds.outWidth, bounds.outHeight,
                anchorX, anchorY, normalizedWidth, normalizedHeight)) return;
        Bitmap bitmap = BitmapFactory.decodeByteArray(png, 0, png.length);
        if (bitmap == null) return;
        runOnUiThread(() -> cursorOverlay.setCursorImage(
                bitmap, anchorX, anchorY, normalizedWidth, normalizedHeight));
    }

    @Override
    public void onMetrics(StreamMetrics metrics) {
        runOnUiThread(() -> {
            lastMetrics = metrics;
            currentTransport = metrics.transport == null ? "unknown" : metrics.transport;
            updateWifiLowLatencyState();
            refreshStreamingStatus();
        });
    }

    @Override
    public void onStreamConfig(VideoStreamConfig config) {
        runOnUiThread(() -> {
            lastStreamConfig = config;
            updateVideoViewport();
            surfaceFrameRateLifecycle.onStreamConfig(config.fps);
            refreshStreamingStatus();
        });
    }

    @Override
    public void onTransportChanged(String transport) {
        runOnUiThread(() -> {
            currentTransport = transport == null ? "unknown" : transport;
            updateWifiLowLatencyState();
        });
    }

    @Override
    public float currentDisplayRefreshRate() {
        return currentRefreshRate();
    }

    @Override
    public float requestedSurfaceFrameRate() {
        return requestedSurfaceRefreshRate;
    }

    @Override
    public String surfaceFrameRateApplyResult() {
        return surfaceFrameRateStatus;
    }

    @Override
    public WifiLowLatencyLifecycle.Snapshot wifiLowLatencySnapshot() {
        return wifiLowLatencyLifecycle.snapshot();
    }

    @Override
    public void onRequestPermissionsResult(int requestCode, String[] permissions, int[] grantResults) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults);
        if (requestCode == REQUEST_NEARBY_WIFI && hasNearbyWifiPermission()) {
            if (server != null) {
                server.enableWifiAdvertising();
            }
            receiverLifecycle.reevaluate();
        } else if (requestCode == REQUEST_NEARBY_WIFI) {
            setStatus("需要附近设备权限才能在 WiFi 中被 Mac 发现");
        }
    }

    private void buildUi() {
        root = new FrameLayout(this);
        root.setBackgroundColor(Color.BLACK);
        surfaceView = new ReceiverSurfaceView(this);
        root.addView(surfaceView, new FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT));

        cursorOverlay = new CursorOverlayView(this);
        root.addView(cursorOverlay, new FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT));
        root.addOnLayoutChangeListener((view, left, top, right, bottom, oldLeft, oldTop, oldRight, oldBottom) -> {
            if (right - left != oldRight - oldLeft || bottom - top != oldBottom - oldTop) updateVideoViewport();
        });

        idlePanel = buildIdlePanel();
        root.addView(idlePanel, new FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT));

        statusView = new TextView(this);
        statusView.setTextColor(Color.WHITE);
        statusView.setTextSize(15);
        statusView.setText(currentStatus);
        statusView.setPadding(dp(16), dp(12), dp(16), dp(12));
        statusView.setMinHeight(dp(48));
        statusView.setFocusable(true);
        statusView.setBackgroundColor(0x99000000);
        statusView.setOnClickListener(v -> showSettingsDialog());
        FrameLayout.LayoutParams statusParams = new FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.WRAP_CONTENT,
                FrameLayout.LayoutParams.WRAP_CONTENT,
                Gravity.TOP | Gravity.START);
        statusParams.setMargins(dp(16), dp(16), dp(88), dp(16));
        root.addView(statusView, statusParams);
        streamSettingsButton = ui.button("设置");
        streamSettingsButton.setContentDescription("打开设置与帮助");
        streamSettingsButton.setOnClickListener(v -> showSettingsDialog());
        FrameLayout.LayoutParams settingsParams = new FrameLayout.LayoutParams(
                dp(72), dp(48), Gravity.TOP | Gravity.END);
        settingsParams.setMargins(dp(12), dp(16), dp(12), 0);
        root.addView(streamSettingsButton, settingsParams);
        setContentView(root);
        updateStatusOverlayVisibility();

        surfaceView.getHolder().addCallback(new SurfaceHolder.Callback() {
            @Override
            public void surfaceCreated(SurfaceHolder holder) {
                activeSurface = holder;
                surfaceFrameRateLifecycle.onSurfaceCreated();
                updateWifiLowLatencyState();
                receiverLifecycle.onSurfaceCreated();
            }

            @Override
            public void surfaceChanged(SurfaceHolder holder, int format, int width, int height) {
                if (server != null) {
                    server.updateDisplay(currentDisplaySpec());
                }
                surfaceFrameRateLifecycle.onSurfaceChanged();
            }

            @Override
            public void surfaceDestroyed(SurfaceHolder holder) {
                surfaceFrameRateLifecycle.onSurfaceDestroyed();
                activeSurface = null;
                updateWifiLowLatencyState();
                receiverLifecycle.onSurfaceDestroyed();
            }
        });

        surfaceView.setContentDescription("远程画面，单指点击或拖动，双指滚动");
        surfaceView.setOnTouchListener(this::handleTouch);
    }

    private void updateVideoViewport() {
        if (root == null || surfaceView == null || cursorOverlay == null) return;
        VideoViewport rect = VideoViewport.fit(root.getWidth(), root.getHeight(), lastStreamConfig.width, lastStreamConfig.height);
        if (rect.width == 0 || rect.height == 0) return;
        FrameLayout.LayoutParams old = (FrameLayout.LayoutParams) surfaceView.getLayoutParams();
        if (old.width == rect.width && old.height == rect.height && old.gravity == Gravity.CENTER) return;
        cancelTouchGesture();
        for (View child : new View[] {surfaceView, cursorOverlay}) {
            FrameLayout.LayoutParams params = new FrameLayout.LayoutParams(rect.width, rect.height, Gravity.CENTER);
            child.setLayoutParams(params);
        }
    }

    private void cancelPendingHold() {
        if (pendingTouchHold != null && surfaceView != null) surfaceView.removeCallbacks(pendingTouchHold);
        pendingTouchHold = null;
    }

    private void cancelTouchGesture() {
        cancelPendingHold();
        if (touchGesture != null) sendTouchEvents(touchGesture.cancel());
        touchGesture = null;
        scrollGesture.end();
    }

    private void scheduleTouchHold() {
        OpenDisplayServer owner = server;
        TouchGestureCoordinator gesture = touchGesture;
        pendingTouchHold = () -> {
            pendingTouchHold = null;
            if (server == owner && touchGesture == gesture && streaming && foreground) sendTouchEvents(gesture.commitHold());
        };
        surfaceView.postDelayed(pendingTouchHold, TouchGestureCoordinator.HOLD_DELAY_MS);
    }

    private View buildIdlePanel() {
        ScrollView scroll = new ScrollView(this);
        scroll.setFillViewport(true);
        scroll.setBackgroundColor(ui.background);

        LinearLayout content = new LinearLayout(this);
        content.setOrientation(LinearLayout.VERTICAL);
        content.setGravity(Gravity.CENTER_HORIZONTAL);
        content.setPadding(dp(24), dp(32), dp(24), dp(24));
        FrameLayout contentHost = new FrameLayout(this);
        scroll.addView(contentHost, new ScrollView.LayoutParams(
                ScrollView.LayoutParams.MATCH_PARENT, ScrollView.LayoutParams.WRAP_CONTENT));
        FrameLayout.LayoutParams contentParams = new FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.WRAP_CONTENT,
                Gravity.TOP | Gravity.CENTER_HORIZONTAL);
        contentHost.addView(content, contentParams);
        contentHost.addOnLayoutChangeListener((v, left, top, right, bottom, oldLeft, oldTop, oldRight, oldBottom) -> {
            int width = Math.min(right - left, dp(568));
            if (width > 0 && content.getLayoutParams().width != width) {
                content.getLayoutParams().width = width;
                content.requestLayout();
            }
        });

        ImageView logo = new ImageView(this);
        logo.setImageResource(getResources().getIdentifier("app_logo", "drawable", getPackageName()));
        logo.setAdjustViewBounds(true);
        logo.setImportantForAccessibility(View.IMPORTANT_FOR_ACCESSIBILITY_NO);
        content.addView(logo, new LinearLayout.LayoutParams(dp(80), dp(80)));

        TextView title = text("DisplayWeave", 28, ui.primary, true);
        title.setGravity(Gravity.CENTER);
        title.setPadding(0, dp(16), 0, 0);
        content.addView(title, matchWrap());

        idleStatusView = text(currentStatus, 15, ui.secondary, false);
        idleStatusView.setGravity(Gravity.CENTER);
        idleStatusView.setPadding(0, dp(8), 0, dp(24));
        content.addView(idleStatusView, matchWrap());

        LinearLayout guide = ui.panel();
        ui.step(guide, 1, "准备连接", "在 Mac 打开 DisplayWeave 或 OpenDisplay，加入同一局域网，或连接已授权 USB 调试的设备。");
        ui.step(guide, 2, "选择连接客户端", "DisplayWeave 使用加密配对邀请；OpenDisplay 选择下方兼容入口，无需邀请。");
        ui.step(guide, 3, "选择这台设备", "在 Mac 的设备列表中连接本机，选择扩展或镜像，并保持接收端打开。");
        content.addView(guide, matchWrap());

        connectionModeButton = ui.button("");
        connectionModeButton.setOnClickListener(v -> securitySettings.showConnectionModes());
        LinearLayout.LayoutParams modeParams = matchWrap();
        modeParams.setMargins(0, dp(16), 0, dp(8));
        content.addView(connectionModeButton, modeParams);
        refreshConnectionModeUi();

        Button settings = ui.primaryButton("配对与连接设置");
        settings.setOnClickListener(v -> showSettingsDialog());
        content.addView(settings, matchWrap());

        TextView footnote = text("兼容模式未加密，请使用可信网络。串流时右上角始终提供设置入口；USB 调试授权会信任当前 Mac。", 13,
                ui.secondary, false);
        footnote.setPadding(0, dp(16), 0, 0);
        content.addView(footnote, matchWrap());
        return scroll;
    }

    private void refreshConnectionModeUi() {
        if (connectionModeButton != null) {
            connectionModeButton.setText(AndroidSecuritySettings.legacyEnabled(this)
                    ? "连接客户端：OpenDisplay 兼容 · 未加密" : "连接客户端：DisplayWeave 加密");
        }
    }

    private TextView cardText(String value) {
        return ui.card(value);
    }

    private void showSettingsDialog() {
        LinearLayout content = new LinearLayout(this);
        content.setOrientation(LinearLayout.VERTICAL);
        content.setPadding(dp(20), dp(10), dp(20), 0);

        content.addView(ui.heading("连接与配对"), matchWrap());
        content.addView(text("连接状态：" + currentStatus, 15, ui.primary, false), matchWrap());
        content.addView(text("服务端口：9000\n设备标识：" + InstallId.get(this), 13,
                ui.secondary, false), matchWrap());

        Button security = ui.button("安全与配对");
        security.setOnClickListener(v -> securitySettings.show());
        content.addView(security, matchWrap());

        content.addView(ui.heading("显示与操作"), matchWrap());
        CheckBox keepAwake = new CheckBox(this);
        keepAwake.setText("保持屏幕常亮");
        keepAwake.setChecked(prefs.getBoolean(KEY_KEEP_AWAKE, true));
        keepAwake.setOnCheckedChangeListener((button, checked) -> {
            prefs.edit().putBoolean(KEY_KEEP_AWAKE, checked).apply();
            applyKeepAwakePreference();
        });
        content.addView(keepAwake, matchWrap());

        CheckBox showStatus = new CheckBox(this);
        showStatus.setText("串流时显示状态浮层");
        showStatus.setChecked(prefs.getBoolean(KEY_SHOW_STATUS, true));
        showStatus.setOnCheckedChangeListener((button, checked) -> {
            prefs.edit().putBoolean(KEY_SHOW_STATUS, checked).apply();
            updateStatusOverlayVisibility();
        });
        content.addView(showStatus, matchWrap());

        CheckBox showMetrics = new CheckBox(this);
        showMetrics.setText("显示延迟和帧率");
        showMetrics.setChecked(prefs.getBoolean(KEY_SHOW_METRICS, false));
        showMetrics.setOnCheckedChangeListener((button, checked) -> {
            prefs.edit().putBoolean(KEY_SHOW_METRICS, checked).apply();
            refreshStreamingStatus();
        });
        content.addView(showMetrics, matchWrap());

        if (streaming) {
            content.addView(ui.heading("当前画面"), matchWrap());
            TextView diagnostics = text(detailedMetricsText(), 13, ui.secondary, false);
            diagnostics.setTextIsSelectable(true);
            content.addView(diagnostics, matchWrap());
        }
        content.addView(ui.heading("画质与延迟"), matchWrap());
        Button quality = ui.button("接收分辨率：" + currentDisplayProfile().label);
        quality.setOnClickListener(v -> showDisplayProfileDialog());
        content.addView(quality, matchWrap());
        content.addView(text("Mac 的画质设置还会影响最终分辨率。文字不清晰时，先选原生分辨率，并在 Mac 选择高画质。", 13, ui.secondary, false), matchWrap());

        Button decoderLowLatency = ui.button("");
        decoderLowLatency.setText("解码器低延迟："
                + currentDecoderLowLatencyMode().label);
        decoderLowLatency.setOnClickListener(v -> showDecoderLowLatencyDialog());
        content.addView(decoderLowLatency, matchWrap());

        Button wifiLowLatency = ui.button("");
        wifiLowLatency.setText("WiFi 低延迟："
                + currentWifiLowLatencyMode().label);
        wifiLowLatency.setOnClickListener(v -> showWifiLowLatencyDialog());
        content.addView(wifiLowLatency, matchWrap());

        content.addView(ui.heading("更新与帮助"), matchWrap());
        TextView version = text("当前版本：" + installedVersionLabel()
                        + "\n更新状态：" + updateState,
                13, ui.secondary, false);
        version.setPadding(0, dp(10), 0, 0);
        content.addView(version, matchWrap());

        Button checkUpdate = ui.button("");
        checkUpdate.setText("检查更新");
        checkUpdate.setOnClickListener(v -> updateCoordinator.check(true));
        content.addView(checkUpdate, matchWrap());

        TextView help = text("如果 Mac 找不到 Android：确认两台设备在同一局域网，VPN/TUN 没有隔离局域网，"
                + "并允许 Android 的“附近设备/本地网络”权限。点击屏幕后若 Mac 端无反应，请确认 Mac 辅助功能权限已开启。",
                14, ui.secondary, false);
        help.setPadding(0, dp(10), 0, 0);
        content.addView(help, matchWrap());

        if (!hasNearbyWifiPermission() && Build.VERSION.SDK_INT >= 33) {
            Button permission = ui.button("");
            permission.setText("授予附近设备权限");
            permission.setOnClickListener(v -> requestPermissions(
                    new String[] {Manifest.permission.NEARBY_WIFI_DEVICES}, REQUEST_NEARBY_WIFI));
            content.addView(permission, matchWrap());
        }

        ScrollView settingsScroll = new ScrollView(this);
        settingsScroll.addView(content);
        new AlertDialog.Builder(this)
                .setTitle("设置与帮助")
                .setView(settingsScroll)
                .setPositiveButton("完成", null)
                .show();
    }

    private UpdateCoordinator createUpdateCoordinator() {
        return new UpdateCoordinator(this, prefs, new UpdateCoordinator.Listener() {
            @Override
            public void onCheckState(String state) {
                updateState = state;
            }

            @Override
            public void onUpdateAvailable(UpdateManifest manifest) {
                updateState = "发现新版本 " + manifest.versionName;
                if (!canShowDialog()) return;
                new AlertDialog.Builder(MainActivity.this)
                        .setTitle("发现新版本 " + manifest.versionName)
                        .setMessage("更新包会先验证大小、SHA-256、包名、版本和签名证书，"
                                + "验证通过后仍需在 Android 系统界面确认安装。")
                        .setPositiveButton("下载并验证", (dialog, which) ->
                                showUpdateDownloadDialog(manifest))
                        .setNegativeButton("稍后", null)
                        .show();
            }

            @Override
            public void onDownloadProgress(int percent) {
                updateState = "正在下载更新… " + percent + "%";
                if (updateDownloadProgress != null) {
                    updateDownloadProgress.setProgress(percent, true);
                }
                if (updateDownloadProgressText != null) {
                    updateDownloadProgressText.setText("已下载 " + percent + "%");
                }
            }

            @Override
            public void onVerifiedUpdateReady(UpdateManifest manifest) {
                updateState = "更新已验证，等待安装";
                dismissUpdateDownloadDialog();
                if (!canShowDialog()) return;
                new AlertDialog.Builder(MainActivity.this)
                        .setTitle("更新已验证")
                        .setMessage("版本 " + manifest.versionName
                                + " 已通过安全校验。点击安装后会再次确认线上最新版本，"
                                + "然后打开 Android 系统安装界面。更新完成后安装包会在下次启动时自动清理。")
                        .setPositiveButton("安装", (dialog, which) ->
                                updateCoordinator.installPending())
                        .setNegativeButton("稍后", null)
                        .show();
            }

            @Override
            public void onUpdateError(String message, boolean manual) {
                updateState = "更新检查失败：" + message;
                dismissUpdateDownloadDialog();
                if (!manual || !canShowDialog()) return;
                new AlertDialog.Builder(MainActivity.this)
                        .setTitle("无法更新")
                        .setMessage(message)
                        .setPositiveButton("知道了", null)
                        .show();
            }
        });
    }

    private void showUpdateDownloadDialog(UpdateManifest manifest) {
        dismissUpdateDownloadDialog();
        LinearLayout content = new LinearLayout(this);
        content.setOrientation(LinearLayout.VERTICAL);
        content.setPadding(dp(24), dp(12), dp(24), dp(8));

        TextView progressText = text("准备下载…", 14,
                ui.secondary, false);
        content.addView(progressText, matchWrap());

        ProgressBar progress = new ProgressBar(
                this, null, android.R.attr.progressBarStyleHorizontal);
        progress.setIndeterminate(false);
        progress.setMax(100);
        progress.setProgress(0);
        LinearLayout.LayoutParams progressParams = matchWrap();
        progressParams.setMargins(0, dp(12), 0, dp(6));
        content.addView(progress, progressParams);

        AlertDialog dialog = new AlertDialog.Builder(this)
                .setTitle("正在下载 " + manifest.versionName)
                .setView(content)
                .setNegativeButton("隐藏", null)
                .create();
        updateDownloadDialog = dialog;
        updateDownloadProgress = progress;
        updateDownloadProgressText = progressText;
        dialog.setOnDismissListener(ignored -> {
            if (updateDownloadDialog == dialog) {
                updateDownloadDialog = null;
                updateDownloadProgress = null;
                updateDownloadProgressText = null;
            }
        });
        dialog.show();
        updateCoordinator.download(manifest);
    }

    private void dismissUpdateDownloadDialog() {
        AlertDialog dialog = updateDownloadDialog;
        updateDownloadDialog = null;
        updateDownloadProgress = null;
        updateDownloadProgressText = null;
        if (dialog != null && dialog.isShowing()) dialog.dismiss();
    }

    private boolean canShowDialog() {
        return !isFinishing() && (Build.VERSION.SDK_INT < 17 || !isDestroyed());
    }

    private String installedVersionLabel() {
        try {
            android.content.pm.PackageInfo info = getPackageManager()
                    .getPackageInfo(getPackageName(), 0);
            long code = Build.VERSION.SDK_INT >= 28 ? info.getLongVersionCode() : info.versionCode;
            return info.versionName + " (" + code + ")";
        } catch (PackageManager.NameNotFoundException error) {
            return "未知";
        }
    }

    private void showDisplayProfileDialog() {
        DisplayProfile[] profiles = DisplayProfile.values();
        String[] labels = new String[profiles.length];
        int checked = 0;
        DisplayProfile current = currentDisplayProfile();
        for (int i = 0; i < profiles.length; i++) {
            labels[i] = profiles[i].label;
            if (profiles[i] == current) {
                checked = i;
            }
        }
        new AlertDialog.Builder(this)
                .setTitle("画质/分辨率")
                .setSingleChoiceItems(labels, checked, (dialog, which) -> {
                    prefs.edit().putString(KEY_DISPLAY_PROFILE, profiles[which].key).apply();
                    if (server != null) {
                        server.updateDisplay(currentDisplaySpec());
                    }
                    setStatus("已请求 " + profiles[which].label + " 分辨率，Mac 会重新配置画面");
                    dialog.dismiss();
                })
                .setNegativeButton("取消", null)
                .show();
    }

    private void showDecoderLowLatencyDialog() {
        DecoderLowLatencyMode[] modes = DecoderLowLatencyMode.values();
        String[] labels = new String[modes.length];
        int checked = 0;
        DecoderLowLatencyMode current = currentDecoderLowLatencyMode();
        for (int i = 0; i < modes.length; i++) {
            labels[i] = modes[i].label;
            if (modes[i] == current) {
                checked = i;
            }
        }
        new AlertDialog.Builder(this)
                .setTitle("解码器低延迟")
                .setSingleChoiceItems(labels, checked, (dialog, which) -> {
                    DecoderLowLatencyMode selected = modes[which];
                    prefs.edit().putString(
                            KEY_DECODER_LOW_LATENCY, selected.key).apply();
                    if (server != null) {
                        stopServer();
                        startServerIfReady();
                    }
                    setStatus("解码器低延迟已设为" + selected.label
                            + "，正在重新建立有限会话…");
                    dialog.dismiss();
                })
                .setNegativeButton("取消", null)
                .show();
    }

    private void showWifiLowLatencyDialog() {
        WifiLowLatencyMode[] modes = WifiLowLatencyMode.values();
        String[] labels = new String[modes.length];
        int checked = 0;
        WifiLowLatencyMode current = currentWifiLowLatencyMode();
        for (int i = 0; i < modes.length; i++) {
            labels[i] = modes[i].label;
            if (modes[i] == current) {
                checked = i;
            }
        }
        new AlertDialog.Builder(this)
                .setTitle("WiFi 低延迟")
                .setSingleChoiceItems(labels, checked, (dialog, which) -> {
                    WifiLowLatencyMode selected = modes[which];
                    prefs.edit().putString(KEY_WIFI_LOW_LATENCY, selected.key).apply();
                    updateWifiLowLatencyState();
                    setStatus("WiFi 低延迟已设为" + selected.label);
                    dialog.dismiss();
                })
                .setNegativeButton("取消", null)
                .show();
    }

    private void showOnboardingIfNeeded() {
        if (prefs.getBoolean(KEY_ONBOARDING_DISMISSED, false)) {
            return;
        }
        new AlertDialog.Builder(this)
                .setTitle("欢迎使用 DisplayWeave")
                .setMessage("这个 Android 端需要和 Mac 端配合使用。请先在 Mac 上启动 DisplayWeave 或 OpenDisplay，"
                        + "再让两台设备加入同一局域网。DisplayWeave 使用配对邀请；OpenDisplay 在主界面选择兼容模式，然后从 Mac 连接这台设备。")
                .setPositiveButton("知道了", (dialog, which) ->
                        prefs.edit().putBoolean(KEY_ONBOARDING_DISMISSED, true).apply())
                .show();
    }

    private boolean startServerIfReady() {
        if (server != null) {
            return true;
        }
        if (activeSurface == null) {
            return false;
        }
        boolean advertiseWifi = ReceiverPermissionPolicy.shouldAdvertiseWifi(
                hasNearbyWifiPermission());
        try {
            server = new OpenDisplayServer(MainActivity.this, currentDisplaySpec(), MainActivity.this, advertiseWifi);
        } catch (java.io.IOException | java.security.GeneralSecurityException failure) {
            setStatus("安全身份不可用：请在设置 → 安全与配对中重新载入或显式重置身份。" + failure.getMessage());
            return false;
        }
        server.setDecoderLowLatencyMode(currentDecoderLowLatencyMode());
        server.start(activeSurface.getSurface());
        if (!advertiseWifi) {
            setStatus("USB 已就绪；授予附近设备权限后可使用 WiFi 发现");
        }
        return true;
    }

    private void stopServer() {
        if (server == null) {
            return;
        }
        server.stop();
        server = null;
    }

    private DecoderLowLatencyMode currentDecoderLowLatencyMode() {
        return DecoderLowLatencyMode.fromStoredValue(
                prefs.getString(KEY_DECODER_LOW_LATENCY, null));
    }

    private WifiLowLatencyMode currentWifiLowLatencyMode() {
        return WifiLowLatencyMode.fromStoredValue(
                prefs.getString(KEY_WIFI_LOW_LATENCY, null));
    }

    private boolean hasNearbyWifiPermission() {
        return Build.VERSION.SDK_INT < 33
                || checkSelfPermission(Manifest.permission.NEARBY_WIFI_DEVICES)
                == PackageManager.PERMISSION_GRANTED;
    }

    private boolean handleTouch(View view, MotionEvent event) {
        if (!streaming || server == null || view.getWidth() <= 0 || view.getHeight() <= 0) {
            return true;
        }
        if (event.getPointerCount() >= 2 || scrollGesture.isActive()) {
            handleScrollGesture(view, event);
            return true;
        }

        int index = TouchEventMapper.safePointerIndex(
                event.getActionMasked(), event.getActionIndex(), event.getPointerCount());
        if (index < 0) {
            return true;
        }
        double x = Math.max(0, Math.min(1, event.getX(index) / Math.max(1.0, view.getWidth())));
        double y = Math.max(0, Math.min(1, event.getY(index) / Math.max(1.0, view.getHeight())));
        if (touchGesture == null) {
            touchGesture = new TouchGestureCoordinator(dp(10), view.getWidth(), view.getHeight());
        }
        switch (event.getActionMasked()) {
            case MotionEvent.ACTION_DOWN:
                cancelPendingHold();
                sendTouchEvents(touchGesture.begin(x, y));
                scheduleTouchHold();
                break;
            case MotionEvent.ACTION_MOVE:
                sendTouchEvents(touchGesture.move(x, y));
                break;
            case MotionEvent.ACTION_UP:
            case MotionEvent.ACTION_POINTER_UP:
                cancelPendingHold();
                sendTouchEvents(touchGesture.end(x, y));
                view.performClick();
                break;
            case MotionEvent.ACTION_CANCEL:
                cancelTouchGesture();
                break;
            default:
                break;
        }
        return true;
    }

    private void handleScrollGesture(View view, MotionEvent event) {
        cancelPendingHold();
        if (touchGesture != null) {
            sendTouchEvents(touchGesture.cancel());
        }
        if (event.getPointerCount() < 2) {
            scrollGesture.end();
            return;
        }
        double x = (event.getX(0) + event.getX(1)) / 2.0;
        double y = (event.getY(0) + event.getY(1)) / 2.0;
        if (!scrollGesture.isActive()) {
            scrollGesture.begin(x, y, videoScaleInView(view));
            return;
        }
        if (event.getActionMasked() == MotionEvent.ACTION_POINTER_UP
                || event.getActionMasked() == MotionEvent.ACTION_UP
                || event.getActionMasked() == MotionEvent.ACTION_CANCEL) {
            scrollGesture.end();
            return;
        }
        ScrollGestureTracker.Delta delta = scrollGesture.move(x, y);
        if (delta != null && (Math.abs(delta.dx) > 0.01 || Math.abs(delta.dy) > 0.01)) {
            server.sendScroll(delta.dx, delta.dy);
        }
    }

    private void sendTouchEvents(java.util.List<TouchGestureCoordinator.Event> events) {
        if (server == null) return;
        for (TouchGestureCoordinator.Event event : events) {
            server.sendTouch(event.phase, event.x, event.y);
        }
    }

    private double videoScaleInView(View view) {
        double xScale = view.getWidth() / Math.max(1.0, lastStreamConfig.width);
        double yScale = view.getHeight() / Math.max(1.0, lastStreamConfig.height);
        return Math.max(0.001, Math.min(xScale, yScale));
    }

    private void setStatus(String status) {
        currentStatus = status;
        if (statusView != null) {
            statusView.setText(status);
        }
        if (idleStatusView != null) {
            idleStatusView.setText(status);
        }
    }

    private void setStreaming(boolean streaming) {
        this.streaming = streaming;
        if (streaming) {
            surfaceFrameRateLifecycle.onStreamingStarted();
        } else {
            cancelTouchGesture();
            lastMetrics = new StreamMetrics(0, 0, 0, 0);
            surfaceFrameRateLifecycle.onStreamingStopped();
        }
        refreshStreamingStatus();
        updateWifiLowLatencyState();
        idlePanel.setVisibility(streaming ? View.GONE : View.VISIBLE);
        updateStatusOverlayVisibility();
    }

    private void refreshStreamingStatus() {
        if (!streaming) return;
        String value = "正在接收 · " + lastStreamConfig.width + "×" + lastStreamConfig.height;
        if (prefs.getBoolean(KEY_SHOW_METRICS, false)) {
            value += " · " + lastStreamConfig.codec.toUpperCase(Locale.US) + " · 目标 " + lastStreamConfig.fps + " FPS";
            value += "\n呈现 " + lastMetrics.renderedFps + " FPS · RTT " + Math.round(lastMetrics.rttMs) + " ms";
            if (lastMetrics.bitrate > 0) value += " · " + lastMetrics.bitrate / 1_000_000 + " Mbps";
        }
        setStatus(value);
    }

    private String detailedMetricsText() {
        StringBuilder value = new StringBuilder("正在接收");
        value.append(" · ").append(lastStreamConfig.codec.toUpperCase(Locale.US));
        value.append(" · 请求 ").append(lastStreamConfig.fps).append(" FPS");
        if (requestedSurfaceRefreshRate > 0) {
            value.append(" · Surface请求 ")
                    .append(Math.round(requestedSurfaceRefreshRate)).append(" FPS");
        }
        if (lastMetrics.receiverFps > 0) {
            value.append(" · 收 ").append(lastMetrics.receiverFps).append(" FPS");
        }
        if (lastMetrics.decodedFps > 0) {
            value.append(" · 解 ").append(lastMetrics.decodedFps).append(" FPS");
        }
        if (lastMetrics.renderedFps > 0) {
            value.append(" · 渲 ").append(lastMetrics.renderedFps).append(" FPS");
        }
        if (lastMetrics.androidDisplayRefreshRate > 0) {
            value.append(" · 屏幕模式 ")
                    .append(Math.round(lastMetrics.androidDisplayRefreshRate)).append("Hz");
        }
        if (lastMetrics.droppedFramesAndroid > 0) {
            value.append(" · Android丢 ").append(lastMetrics.droppedFramesAndroid);
        }
        if (lastMetrics.queueDepthAndroid > 0) {
            value.append(" · 队列 ").append(lastMetrics.queueDepthAndroid);
        }
        if (lastMetrics.rttMs > 0) {
            value.append(" · RTT ").append(Math.round(lastMetrics.rttMs)).append(" ms");
        }
        if (lastMetrics.endToEndLatencyMs > 0) {
            value.append(" · E2E ").append(lastMetrics.endToEndLatencyMs).append(" ms");
        }
        if (lastMetrics.decodeLatencyMs > 0) {
            value.append(" · 解码 ").append(lastMetrics.decodeLatencyMs).append(" ms");
        }
        if (lastMetrics.latestFrameAgeMs > 0) {
            value.append(" · 帧龄 ").append(lastMetrics.latestFrameAgeMs).append(" ms");
        }
        if (lastMetrics.inputP50Ms > 0) {
            value.append(" · 输入 ").append(Math.round(lastMetrics.inputP50Ms)).append(" ms");
        }
        if (lastMetrics.macCaptureFps > 0) {
            value.append(" · 捕 ").append(lastMetrics.macCaptureFps).append(" FPS");
        }
        if (lastMetrics.encodedFps > 0) {
            value.append(" · 编 ").append(lastMetrics.encodedFps).append(" FPS");
        }
        if (lastMetrics.sentFps > 0) {
            value.append(" · 发 ").append(lastMetrics.sentFps).append(" FPS");
        }
        if (lastMetrics.actualVirtualDisplayRefreshRate > 0) {
            value.append(" · 虚拟屏 ").append(lastMetrics.actualVirtualDisplayRefreshRate).append("Hz");
        }
        if (lastMetrics.encodeLatencyMs > 0) {
            value.append(" · 编码 ").append(lastMetrics.encodeLatencyMs).append(" ms");
        }
        if (lastMetrics.averageFrameSize > 0) {
            value.append(" · 帧 ").append(lastMetrics.averageFrameSize / 1024).append(" KB");
        }
        if (lastMetrics.bitrate > 0) {
            value.append(" · 码率 ").append(lastMetrics.bitrate / 1_000_000).append(" Mbps");
        }
        if (lastMetrics.droppedFramesMac > 0) {
            value.append(" · Mac丢 ").append(lastMetrics.droppedFramesMac);
        }
        if (lastMetrics.queueDepthMac > 0) {
            value.append(" · Mac队列 ").append(lastMetrics.queueDepthMac);
        }
        if (lastMetrics.transport != null && lastMetrics.transport.length() > 0) {
            value.append(" · ").append(lastMetrics.transport.toUpperCase(Locale.US));
        }
        return value.toString();
    }

    private void applyStreamRefreshRate(int fps, String reason) {
        float target = RefreshRateController.chooseRefreshRate(
                fps, supportedRefreshRates(), currentRefreshRate());
        requestedSurfaceRefreshRate = target;

        WindowManager.LayoutParams attrs = getWindow().getAttributes();
        attrs.preferredRefreshRate = target;
        getWindow().setAttributes(attrs);

        surfaceFrameRateStatus = "applied:" + reason
                + ":window=" + Math.round(target) + "Hz";
        if (Build.VERSION.SDK_INT >= 30 && activeSurface != null) {
            try {
                if (Build.VERSION.SDK_INT >= 31) {
                    activeSurface.getSurface().setFrameRate(
                            target,
                            android.view.Surface.FRAME_RATE_COMPATIBILITY_FIXED_SOURCE,
                            android.view.Surface.CHANGE_FRAME_RATE_ONLY_IF_SEAMLESS);
                } else {
                    activeSurface.getSurface().setFrameRate(
                            target,
                            android.view.Surface.FRAME_RATE_COMPATIBILITY_FIXED_SOURCE);
                }
                surfaceFrameRateStatus += ",surface=onlyIfSeamless";
            } catch (RuntimeException error) {
                surfaceFrameRateStatus += ",surface=failed:" + error.getClass().getSimpleName();
            }
        } else {
            surfaceFrameRateStatus += ",surface=unsupported";
        }
        android.util.Log.i("OpenDisplay", "refresh request: requestedFps=" + fps
                + " displayRefreshRate=" + currentRefreshRate()
                + " selectedRefreshRate=" + target
                + " surfaceFrameRateSetResult=" + surfaceFrameRateStatus);
    }

    private void clearStreamRefreshRate(String reason) {
        WindowManager.LayoutParams attrs = getWindow().getAttributes();
        attrs.preferredRefreshRate = 0f;
        getWindow().setAttributes(attrs);
        surfaceFrameRateStatus = "cleared:" + reason + ":window";
        if (Build.VERSION.SDK_INT >= 30 && activeSurface != null) {
            try {
                activeSurface.getSurface().setFrameRate(
                        0f, android.view.Surface.FRAME_RATE_COMPATIBILITY_DEFAULT);
                surfaceFrameRateStatus += ",surface";
            } catch (RuntimeException error) {
                surfaceFrameRateStatus += ",surface=failed:"
                        + error.getClass().getSimpleName();
            }
        }
    }

    private WifiLowLatencyLifecycle.LockAdapter createWifiLowLatencyLock() {
        if (Build.VERSION.SDK_INT < 29) {
            return null;
        }
        WifiManager manager = (WifiManager) getApplicationContext()
                .getSystemService(WIFI_SERVICE);
        if (manager == null) {
            return null;
        }
        WifiManager.WifiLock lock = manager.createWifiLock(
                WifiManager.WIFI_MODE_FULL_LOW_LATENCY,
                "DisplayWeave:WifiLowLatency");
        lock.setReferenceCounted(false);
        return new WifiLowLatencyLifecycle.LockAdapter() {
            @Override
            public boolean acquire() {
                if (!lock.isHeld()) {
                    lock.acquire();
                }
                return lock.isHeld();
            }

            @Override
            public boolean release() {
                if (lock.isHeld()) {
                    lock.release();
                }
                return !lock.isHeld();
            }

            @Override
            public boolean isHeld() {
                return lock.isHeld();
            }
        };
    }

    private void updateWifiLowLatencyState() {
        if (wifiLowLatencyLifecycle == null) {
            return;
        }
        boolean surfaceValid = activeSurface != null
                && activeSurface.getSurface().isValid();
        wifiLowLatencyLifecycle.update(
                currentWifiLowLatencyMode(), foreground, streaming,
                surfaceValid, currentTransport);
    }

    private float[] supportedRefreshRates() {
        Display display = currentDisplay();
        if (display == null) {
            return new float[] {60f};
        }
        Display.Mode[] modes = display.getSupportedModes();
        float[] rates = new float[modes.length];
        for (int i = 0; i < modes.length; i++) {
            rates[i] = modes[i].getRefreshRate();
        }
        return rates;
    }

    private void updateStatusOverlayVisibility() {
        if (statusView == null) {
            return;
        }
        boolean show = streaming && (prefs == null || prefs.getBoolean(KEY_SHOW_STATUS, true));
        statusView.setVisibility(show ? View.VISIBLE : View.GONE);
        if (streamSettingsButton != null) {
            streamSettingsButton.setVisibility(streaming ? View.VISIBLE : View.GONE);
        }
    }

    private void applyKeepAwakePreference() {
        if (prefs == null || prefs.getBoolean(KEY_KEEP_AWAKE, true)) {
            getWindow().addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
        } else {
            getWindow().clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
        }
    }

    private DisplaySpec currentDisplaySpec() {
        DisplayMetrics metrics = getResources().getDisplayMetrics();
        DisplayProfile profile = currentDisplayProfile();
        if (Build.VERSION.SDK_INT >= 30) {
            Rect bounds = getWindowManager().getCurrentWindowMetrics().getBounds();
            return scaledDisplaySpec(bounds.width(), bounds.height(), metrics.density, profile);
        }
        DisplayMetrics realMetrics = new DisplayMetrics();
        readLegacyRealMetrics(realMetrics);
        return scaledDisplaySpec(realMetrics.widthPixels, realMetrics.heightPixels, realMetrics.density, profile);
    }

    private DisplaySpec scaledDisplaySpec(int width, int height, double density, DisplayProfile profile) {
        int scaledW = Math.max(2, ((int) Math.round(width * profile.scale)) & ~1);
        int scaledH = Math.max(2, ((int) Math.round(height * profile.scale)) & ~1);
        int refreshRate = bucketRefreshRate(currentRefreshRate());
        int displayMaxFps = bucketRefreshRate(maxSupportedRefreshRate(refreshRate));
        int maxFps = CodecCapabilities.maxSupportedFps(
                scaledW, scaledH, displayMaxFps,
                currentDecoderLowLatencyMode());
        String[] supportedCodecs = CodecCapabilities.supportedVideoCodecs();
        String preferredCodec = CodecCapabilities.preferredVideoCodec();
        return new DisplaySpec(scaledW, scaledH, density,
                refreshRate,
                maxFps,
                supportedCodecs,
                preferredCodec,
                deviceModel(),
                Build.VERSION.SDK_INT,
                "wifi");
    }

    private float currentRefreshRate() {
        Display display = currentDisplay();
        return display == null ? 60f : display.getRefreshRate();
    }

    private float maxSupportedRefreshRate(float fallback) {
        Display display = currentDisplay();
        if (display == null) {
            return fallback;
        }
        float max = fallback;
        for (Display.Mode mode : display.getSupportedModes()) {
            max = Math.max(max, mode.getRefreshRate());
        }
        return max;
    }

    private Display currentDisplay() {
        if (Build.VERSION.SDK_INT >= 30) {
            return getDisplay();
        }
        @SuppressWarnings("deprecation")
        Display display = getWindowManager().getDefaultDisplay();
        return display;
    }

    private int bucketRefreshRate(float refreshRate) {
        if (refreshRate >= 110f) return 120;
        if (refreshRate >= 80f) return 90;
        if (refreshRate >= 45f) return 60;
        return 30;
    }

    private String deviceModel() {
        String manufacturer = Build.MANUFACTURER == null ? "" : Build.MANUFACTURER.trim();
        String model = Build.MODEL == null ? "" : Build.MODEL.trim();
        if (manufacturer.length() == 0) {
            return model.length() == 0 ? "Android Tablet" : model;
        }
        if (model.toLowerCase(Locale.US).startsWith(manufacturer.toLowerCase(Locale.US))) {
            return model;
        }
        return manufacturer + " " + model;
    }

    private DisplayProfile currentDisplayProfile() {
        if (prefs == null) {
            return DisplayProfile.NATIVE;
        }
        return DisplayProfile.fromKey(prefs.getString(KEY_DISPLAY_PROFILE, DisplayProfile.NATIVE.key));
    }

    @SuppressWarnings("deprecation")
    private void readLegacyRealMetrics(DisplayMetrics out) {
        getWindowManager().getDefaultDisplay().getRealMetrics(out);
    }

    private TextView text(String value, int sp, int color, boolean bold) {
        return ui.text(value, sp, color, bold);
    }

    private LinearLayout.LayoutParams matchWrap() {
        return new LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT);
    }

    private int dp(int value) {
        return ui.dp(value);
    }
}

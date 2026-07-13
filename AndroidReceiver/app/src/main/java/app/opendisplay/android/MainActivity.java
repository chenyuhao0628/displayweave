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

    private FrameLayout root;
    private SurfaceView surfaceView;
    private CursorOverlayView cursorOverlay;
    private TextView statusView;
    private TextView idleStatusView;
    private View idlePanel;
    private OpenDisplayServer server;
    private SurfaceHolder activeSurface;
    private ReceiverLifecycleCoordinator receiverLifecycle;
    private SharedPreferences prefs;
    private UpdateCoordinator updateCoordinator;
    private String updateState = "尚未检查更新";
    private String currentStatus = "等待启动…";
    private boolean streaming;
    private final ScrollGestureTracker scrollGesture = new ScrollGestureTracker();
    private TouchGestureCoordinator touchGesture;
    private StreamMetrics lastMetrics = new StreamMetrics(0, 0, 0, 0);
    private VideoStreamConfig lastStreamConfig = VideoStreamConfig.DEFAULT;
    private float requestedSurfaceRefreshRate = 60f;
    private String surfaceFrameRateStatus = "not requested";

    @Override
    @SuppressWarnings("deprecation")
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
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
        buildUi();
        applyKeepAwakePreference();
        showOnboardingIfNeeded();
    }

    @Override
    protected void onResume() {
        super.onResume();
        receiverLifecycle.onResume();
        updateCoordinator.resumePendingInstall();
        updateCoordinator.check(false);
    }

    @Override
    protected void onPause() {
        receiverLifecycle.onPause();
        super.onPause();
    }

    @Override
    protected void onDestroy() {
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
    public void onCursor(double x, double y, boolean visible) {
        runOnUiThread(() -> cursorOverlay.moveCursor(x, y, visible));
    }

    @Override
    public void onCursorImage(byte[] png, double anchorX, double anchorY,
                              double normalizedWidth, double normalizedHeight) {
        Bitmap bitmap = BitmapFactory.decodeByteArray(png, 0, png.length);
        if (bitmap == null) {
            return;
        }
        runOnUiThread(() -> cursorOverlay.setCursorImage(
                bitmap, anchorX, anchorY, normalizedWidth, normalizedHeight));
    }

    @Override
    public void onMetrics(StreamMetrics metrics) {
        runOnUiThread(() -> {
            lastMetrics = metrics;
            refreshStreamingStatus();
        });
    }

    @Override
    public void onStreamConfig(VideoStreamConfig config) {
        runOnUiThread(() -> {
            lastStreamConfig = config;
            requestStreamRefreshRate(config.fps);
            refreshStreamingStatus();
        });
    }

    @Override
    public float currentDisplayRefreshRate() {
        return currentRefreshRate();
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
        surfaceView = new SurfaceView(this);
        root.addView(surfaceView, new FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT));

        cursorOverlay = new CursorOverlayView(this);
        root.addView(cursorOverlay, new FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT));

        idlePanel = buildIdlePanel();
        root.addView(idlePanel, new FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT));

        statusView = new TextView(this);
        statusView.setTextColor(Color.WHITE);
        statusView.setTextSize(15);
        statusView.setText(currentStatus);
        statusView.setPadding(18, 12, 18, 12);
        statusView.setBackgroundColor(0x99000000);
        statusView.setOnClickListener(v -> showSettingsDialog());
        FrameLayout.LayoutParams statusParams = new FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.WRAP_CONTENT,
                FrameLayout.LayoutParams.WRAP_CONTENT,
                Gravity.TOP | Gravity.START);
        statusParams.setMargins(18, 18, 18, 18);
        root.addView(statusView, statusParams);
        setContentView(root);
        updateStatusOverlayVisibility();

        surfaceView.getHolder().addCallback(new SurfaceHolder.Callback() {
            @Override
            public void surfaceCreated(SurfaceHolder holder) {
                activeSurface = holder;
                receiverLifecycle.onSurfaceCreated();
            }

            @Override
            public void surfaceChanged(SurfaceHolder holder, int format, int width, int height) {
                if (server != null) {
                    server.updateDisplay(currentDisplaySpec());
                }
                requestStreamRefreshRate(lastStreamConfig.fps);
            }

            @Override
            public void surfaceDestroyed(SurfaceHolder holder) {
                activeSurface = null;
                receiverLifecycle.onSurfaceDestroyed();
            }
        });

        surfaceView.setOnTouchListener(this::handleTouch);
    }

    private View buildIdlePanel() {
        ScrollView scroll = new ScrollView(this);
        scroll.setFillViewport(true);
        scroll.setBackgroundColor(0xFFF7F9FC);

        LinearLayout content = new LinearLayout(this);
        content.setOrientation(LinearLayout.VERTICAL);
        content.setGravity(Gravity.CENTER_HORIZONTAL);
        content.setPadding(36, 42, 36, 28);
        scroll.addView(content, new ScrollView.LayoutParams(
                ScrollView.LayoutParams.MATCH_PARENT,
                ScrollView.LayoutParams.WRAP_CONTENT));

        ImageView logo = new ImageView(this);
        logo.setImageResource(getResources().getIdentifier("app_logo", "drawable", getPackageName()));
        logo.setAdjustViewBounds(true);
        content.addView(logo, new LinearLayout.LayoutParams(dp(118), dp(118)));

        TextView title = text("DisplayWeave Android", 30, Color.rgb(20, 24, 34), true);
        title.setGravity(Gravity.CENTER);
        content.addView(title, matchWrap());

        idleStatusView = text(currentStatus, 15, Color.rgb(78, 91, 112), false);
        idleStatusView.setGravity(Gravity.CENTER);
        idleStatusView.setPadding(0, dp(8), 0, dp(24));
        content.addView(idleStatusView, matchWrap());

        content.addView(cardText("1. 在 Mac 上启动 DisplayWeave Mac 端\n"
                + "2. 保持 Android 与 Mac 在同一 WiFi\n"
                + "3. 在 Mac 端 WiFi 列表中选择 DisplayWeave Android\n"
                + "4. 成功后会自动切换到全屏副屏画面"));

        Button settings = new Button(this);
        settings.setText("设置与帮助");
        settings.setOnClickListener(v -> showSettingsDialog());
        LinearLayout.LayoutParams buttonParams = matchWrap();
        buttonParams.setMargins(0, dp(24), 0, dp(8));
        content.addView(settings, buttonParams);

        TextView footnote = text("提示：串流中可在 Android 最近任务里返回此界面；状态浮层可在设置中关闭。", 13,
                Color.rgb(117, 128, 145), false);
        footnote.setGravity(Gravity.CENTER);
        footnote.setPadding(0, dp(8), 0, 0);
        content.addView(footnote, matchWrap());
        return scroll;
    }

    private TextView cardText(String value) {
        TextView view = text(value, 16, Color.rgb(37, 45, 58), false);
        view.setLineSpacing(dp(4), 1.0f);
        view.setPadding(dp(20), dp(18), dp(20), dp(18));
        view.setBackgroundColor(Color.WHITE);
        return view;
    }

    private void showSettingsDialog() {
        LinearLayout content = new LinearLayout(this);
        content.setOrientation(LinearLayout.VERTICAL);
        content.setPadding(dp(20), dp(10), dp(20), 0);

        content.addView(text("连接状态：" + currentStatus, 15, Color.rgb(36, 45, 60), false), matchWrap());
        content.addView(text("服务端口：9000\n设备标识：" + InstallId.get(this), 13,
                Color.rgb(95, 105, 120), false), matchWrap());

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
        showMetrics.setChecked(prefs.getBoolean(KEY_SHOW_METRICS, true));
        showMetrics.setOnCheckedChangeListener((button, checked) -> {
            prefs.edit().putBoolean(KEY_SHOW_METRICS, checked).apply();
            refreshStreamingStatus();
        });
        content.addView(showMetrics, matchWrap());

        Button quality = new Button(this);
        quality.setText("画质/分辨率：" + currentDisplayProfile().label);
        quality.setOnClickListener(v -> showDisplayProfileDialog());
        content.addView(quality, matchWrap());

        TextView version = text("当前版本：" + installedVersionLabel()
                        + "\n更新状态：" + updateState,
                13, Color.rgb(95, 105, 120), false);
        version.setPadding(0, dp(10), 0, 0);
        content.addView(version, matchWrap());

        Button checkUpdate = new Button(this);
        checkUpdate.setText("检查更新");
        checkUpdate.setOnClickListener(v -> updateCoordinator.check(true));
        content.addView(checkUpdate, matchWrap());

        TextView help = text("如果 Mac 找不到 Android：确认两台设备在同一局域网，VPN/TUN 没有隔离局域网，"
                + "并允许 Android 的“附近设备/本地网络”权限。点击屏幕后若 Mac 端无反应，请确认 Mac 辅助功能权限已开启。",
                14, Color.rgb(82, 94, 112), false);
        help.setPadding(0, dp(10), 0, 0);
        content.addView(help, matchWrap());

        if (!hasNearbyWifiPermission() && Build.VERSION.SDK_INT >= 33) {
            Button permission = new Button(this);
            permission.setText("授予附近设备权限");
            permission.setOnClickListener(v -> requestPermissions(
                    new String[] {Manifest.permission.NEARBY_WIFI_DEVICES}, REQUEST_NEARBY_WIFI));
            content.addView(permission, matchWrap());
        }

        new AlertDialog.Builder(this)
                .setTitle("设置与帮助")
                .setView(content)
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
                                updateCoordinator.download(manifest))
                        .setNegativeButton("稍后", null)
                        .show();
            }

            @Override
            public void onDownloadProgress(int percent) {
                updateState = "正在下载更新… " + percent + "%";
            }

            @Override
            public void onVerifiedUpdateReady(UpdateManifest manifest) {
                updateState = "更新已验证，等待安装";
                if (!canShowDialog()) return;
                new AlertDialog.Builder(MainActivity.this)
                        .setTitle("更新已验证")
                        .setMessage("版本 " + manifest.versionName
                                + " 已通过安全校验。点击安装后将打开 Android 系统安装界面。")
                        .setPositiveButton("安装", (dialog, which) ->
                                updateCoordinator.installPending())
                        .setNegativeButton("稍后", null)
                        .show();
            }

            @Override
            public void onUpdateError(String message, boolean manual) {
                updateState = "更新检查失败：" + message;
                if (!manual || !canShowDialog()) return;
                new AlertDialog.Builder(MainActivity.this)
                        .setTitle("无法更新")
                        .setMessage(message)
                        .setPositiveButton("知道了", null)
                        .show();
            }
        });
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

    private void showOnboardingIfNeeded() {
        if (prefs.getBoolean(KEY_ONBOARDING_DISMISSED, false)) {
            return;
        }
        new AlertDialog.Builder(this)
                .setTitle("欢迎使用 DisplayWeave")
                .setMessage("这个 Android 端需要和 Mac 端配合使用。请先在 Mac 上启动 DisplayWeave，"
                        + "再让两台设备连接同一个 WiFi，随后在 Mac 端选择这台 Android 设备。")
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
        server = new OpenDisplayServer(MainActivity.this, currentDisplaySpec(),
                MainActivity.this, advertiseWifi);
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

    private boolean hasNearbyWifiPermission() {
        return Build.VERSION.SDK_INT < 33
                || checkSelfPermission(Manifest.permission.NEARBY_WIFI_DEVICES)
                == PackageManager.PERMISSION_GRANTED;
    }

    private boolean handleTouch(View view, MotionEvent event) {
        if (server == null || view.getWidth() <= 0 || view.getHeight() <= 0) {
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
        double x = event.getX(index) / Math.max(1.0, view.getWidth());
        double y = event.getY(index) / Math.max(1.0, view.getHeight());
        if (touchGesture == null) {
            touchGesture = new TouchGestureCoordinator(10.0 / Math.max(view.getWidth(), view.getHeight()));
        }
        switch (event.getActionMasked()) {
            case MotionEvent.ACTION_DOWN:
                sendTouchEvents(touchGesture.begin(x, y));
                break;
            case MotionEvent.ACTION_MOVE:
                sendTouchEvents(touchGesture.move(x, y));
                break;
            case MotionEvent.ACTION_UP:
            case MotionEvent.ACTION_POINTER_UP:
                sendTouchEvents(touchGesture.end(x, y));
                break;
            case MotionEvent.ACTION_CANCEL:
                sendTouchEvents(touchGesture.cancel());
                break;
            default:
                break;
        }
        return true;
    }

    private void handleScrollGesture(View view, MotionEvent event) {
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
        for (TouchGestureCoordinator.Event event : events) {
            server.sendTouch(event.phase, event.x, event.y);
        }
    }

    private double videoScaleInView(View view) {
        DisplaySpec spec = currentDisplaySpec();
        double xScale = view.getWidth() / Math.max(1.0, spec.pixelsWide);
        double yScale = view.getHeight() / Math.max(1.0, spec.pixelsHigh);
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
        idlePanel.setVisibility(streaming ? View.GONE : View.VISIBLE);
        updateStatusOverlayVisibility();
    }

    private void refreshStreamingStatus() {
        if (!streaming || !prefs.getBoolean(KEY_SHOW_METRICS, true)) {
            return;
        }
        StringBuilder value = new StringBuilder("正在接收");
        value.append(" · ").append(lastStreamConfig.codec.toUpperCase(Locale.US));
        value.append(" · 请求 ").append(lastStreamConfig.fps).append(" FPS");
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
            value.append(" · 屏幕实际 ")
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
        setStatus(value.toString());
    }

    private void requestStreamRefreshRate(int fps) {
        float target = RefreshRateController.chooseRefreshRate(
                fps, supportedRefreshRates(), currentRefreshRate());
        requestedSurfaceRefreshRate = target;

        WindowManager.LayoutParams attrs = getWindow().getAttributes();
        attrs.preferredRefreshRate = target;
        getWindow().setAttributes(attrs);

        surfaceFrameRateStatus = "window=" + Math.round(target) + "Hz";
        if (Build.VERSION.SDK_INT >= 30 && activeSurface != null) {
            try {
                activeSurface.getSurface().setFrameRate(
                        target,
                        android.view.Surface.FRAME_RATE_COMPATIBILITY_FIXED_SOURCE);
                surfaceFrameRateStatus += ", surface=set";
            } catch (RuntimeException error) {
                surfaceFrameRateStatus += ", surface=failed:" + error.getClass().getSimpleName();
            }
        } else {
            surfaceFrameRateStatus += ", surface=unsupported";
        }
        android.util.Log.i("OpenDisplay", "refresh request: requestedFps=" + fps
                + " displayRefreshRate=" + currentRefreshRate()
                + " selectedRefreshRate=" + target
                + " surfaceFrameRateSetResult=" + surfaceFrameRateStatus);
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
        int maxFps = bucketRefreshRate(maxSupportedRefreshRate(refreshRate));
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
        TextView view = new TextView(this);
        view.setText(value);
        view.setTextSize(sp);
        view.setTextColor(color);
        if (bold) {
            view.setTypeface(android.graphics.Typeface.DEFAULT_BOLD);
        }
        return view;
    }

    private LinearLayout.LayoutParams matchWrap() {
        return new LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT);
    }

    private int dp(int value) {
        return (int) (value * getResources().getDisplayMetrics().density + 0.5f);
    }
}

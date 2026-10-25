import SwiftUI

/// Presentation-only bindings; sender pipeline ownership stays in SenderController.
struct SenderSettingsView: View {
    @AppStorage("settingsTab") private var selectedTab = "stream"
    @AppStorage(DesktopInputProtocol.consentKey) private var allowMacDesktopInput = false
    @ObservedObject var controller: SenderController
    @StateObject private var permissions = PermissionMonitor()
    @State private var benchmarkScene = BenchmarkScene.staticDesktop
    @State private var benchmarkDuration = BenchmarkDuration.standard
    private var bitratePresets: [BitratePreset] { controller.settings.availableBitratePresets }

    private func setting<Value>(_ key: WritableKeyPath<StreamSettings, Value>) -> Binding<Value> {
        Binding(get: { controller.settings[keyPath: key] }, set: { value in
            var updated = controller.settings
            updated[keyPath: key] = value
            updated.normalizeBitratePreset()
            guard updated != controller.settings else { return }
            controller.settings = updated
            controller.restartAll()
        })
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            Form { Section("画质与带宽") { streamControls } }
                .tabItem { Label("串流", systemImage: "slider.horizontal.3") }.tag("stream")
            Form {
                Section("设备连接") { connectionControls }
                Section("应用与桌面") { generalControls }
            }
                .tabItem { Label("通用", systemImage: "gearshape") }.tag("general")
            Form { permissionControls; PencilShortcutSettings(); Section("诊断") { diagnosticControls } }
                .tabItem { Label("权限与诊断", systemImage: "checkmark.shield") }.tag("permissions")
            Form { TransportSecuritySettings(permitsSending: true) }
                .tabItem { Label("安全与配对", systemImage: "lock.shield") }.tag("security")
        }
        .tint(.blue)
        .formStyle(.grouped)
        .padding(12)
        .frame(minWidth: 540, minHeight: 520)
    }

    @ViewBuilder private var streamControls: some View {
    VStack(alignment: .leading, spacing: 4) {
        Picker("帧率上限", selection: setting(\.fpsMode)) {
            ForEach(StreamFpsMode.allCases, id: \.self) { mode in
                Text(mode.label).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        Text("30 fps 适合静态办公；60 fps 兼顾日常使用；90／120 fps 需要接收屏幕与解码器支持。实际生效值显示在设备卡片中。")
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    VStack(alignment: .leading, spacing: 4) {
        Picker("能力不足时", selection: setting(\.priority)) {
            ForEach(StreamPriority.allCases, id: \.self) { Text($0.label).tag($0) }
        }.pickerStyle(.segmented)
        Text(controller.settings.priority == .resolution
             ? "Apple 接收端优先保留文字细节，必要时降低帧率。例如 4K 可能以 60 fps 生效。"
             : "Apple 接收端优先达到所选帧率上限，必要时降低编码分辨率；桌面布局保持不变。")
            .font(.caption).foregroundStyle(.secondary)
    }

    VStack(alignment: .leading, spacing: 4) {
        Picker("编码", selection: setting(\.codecMode)) {
            ForEach(StreamCodecMode.allCases, id: \.self) { mode in
                Text(mode.label).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        Text("自动选择双方支持的编码；HEVC 初始化失败时回退 H.264。")
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    VStack(alignment: .leading, spacing: 4) {
        Picker("画质", selection: setting(\.quality)) {
            ForEach(StreamQuality.allCases, id: \.self) { q in
                Text(q.label).tag(q)
            }
        }
        Text(controller.settings.quality.explanation)
            .font(.caption)
            .foregroundStyle(.secondary)
        Text("每台设备的桌面分辨率在连接列表单独选择；这里的画质只缩放编码，不改变桌面布局。镜像保留发送端画面比例，并适配接收端解码尺寸。")
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    VStack(alignment: .leading, spacing: 4) {
        Picker("码率", selection: setting(\.bitrateMode)) {
            ForEach(BitrateMode.allCases, id: \.self) { mode in
                Text(mode.label).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        if controller.settings.bitrateMode != .auto {
            Picker("请求码率", selection: setting(\.bitratePreset)) {
                ForEach(bitratePresets, id: \.self) { preset in
                    Text(preset.label).tag(preset)
                }
            }
        }
        if controller.settings.bitrateMode == .manual {
            Text("这是请求值，最终按每台设备协商：H.264 最高 100 Mbps；HEVC 局域网最高 100、USB 最高 160 Mbps。自动连接或编码回退时，以设备卡片的生效目标为准。")
                .font(.caption).foregroundStyle(.secondary)
        }
        if controller.settings.bitrateMode == .benchmark {
            Text("实验模式：可能增加延迟和排队，仅用于本地测试。")
                .font(.caption)
                .foregroundStyle(.orange)
        } else if controller.settings.bitrateMode == .auto {
            Text("根据发送排队、接收端压力和时延调整；链路恢复后逐步恢复清晰度。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    }
    @ViewBuilder private var connectionControls: some View {
    VStack(alignment: .leading, spacing: 4) {
        Picker("连接方式", selection: setting(\.transportMode)) {
            ForEach(StreamTransportMode.allCases, id: \.self) { mode in
                Text(mode.label).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        Text("自动模式优先 USB；Android USB 不可用时尝试同一设备的局域网连接。")
            .font(.caption)
            .foregroundStyle(.secondary)
    }
    VStack(alignment: .leading, spacing: 8) {
        Toggle("自动连接直连 Mac", isOn: $controller.autoConnectDirectMac)
        Text("仅在自动或局域网模式下生效。识别 Thunderbolt Bridge／链路本地以太网候选；手动断开后停止自动连接。普通 USB-C 线不一定能建立网络。")
            .font(.caption)
            .foregroundStyle(.secondary)
    }
    VStack(alignment: .leading, spacing: 8) {
        Toggle("Mac 有线／无线自动切换", isOn: $controller.autoSwitchMacLAN)
        Text("仅在自动模式下生效。已连接的同一台 Mac 出现稳定有线候选时切换；连接失效后有限重试其他接口。切换会短暂中断画面，手动断开或取消会停止恢复。")
            .font(.caption).foregroundStyle(.secondary)
    }
    VStack(alignment: .leading, spacing: 8) {
        Text(controller.androidAdbStatus)
            .font(.caption)
            .foregroundStyle(.secondary)
        DisclosureGroup("Android ADB 设置") {
            TextField("ADB 路径（留空自动查找）",
                      text: $controller.androidAdbPath)
            Text("自动依次检查自定义路径、PATH、ANDROID_HOME、ANDROID_SDK_ROOT、用户 Android SDK 和 Homebrew。USB 调试授权代表设备信任当前 Mac。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    }
    @ViewBuilder private var generalControls: some View {
    VStack(alignment: .leading, spacing: 4) {
        Picker("显示位置", selection: $controller.presentation) {
            ForEach(AppPresentation.allCases, id: \.self) { p in
                Text(p.label).tag(p)
            }
        }
        if controller.presentation == .background {
            Text("不会显示菜单栏或程序坞图标，串流会继续运行。需要打开此窗口时，请从 Spotlight 或 Finder 再次启动 DisplayWeave。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    LabeledContent("显示器布局") {
        Button("排列显示器…") {
            if let url = URL(string: "x-apple.systempreferences:com.apple.Displays-Settings.extension") {
                NSWorkspace.shared.open(url)
            }
        }
        .controlSize(.small)
    }
    .help("打开“系统设置”→“显示器”，你可以在那里调整扩展显示器相对 Mac 屏幕的位置。每台设备都会作为独立显示器出现，并使用设备名称。")

    }
    @ViewBuilder private var permissionControls: some View {
    Section("权限") {
        Toggle("允许接收端 Mac 的键鼠回传", isOn: $allowMacDesktopInput)
        Text("默认关闭。仅允许已配对的加密 Mac 连接；还需授予辅助功能权限，并在接收端开启回传。关闭后释放远端按键。")
            .font(.caption).foregroundStyle(.secondary)
        permissionRow(
            "屏幕录制",
            granted: permissions.screenRecording,
            help: "用于捕获显示器画面。",
            anchor: "Privacy_ScreenCapture",
            request: { permissions.requestScreenRecording() }
        )
        permissionRow(
            "辅助功能",
            granted: permissions.accessibility,
            help: "用于接收设备上的触摸、滚动和已授权的 Mac 键鼠输入。",
            anchor: "Privacy_Accessibility",
            request: { permissions.requestAccessibility() }
        )
        // macOS offers no API to query Local Network access, so
        // infer from discovery results and let the user check.
        permissionRow(
            "本地网络",
            granted: !controller.discovered.isEmpty,
            uncertain: controller.discovered.isEmpty,
            help: "局域网模式（Wi-Fi/以太网）需要此权限。如果设备列表为空，请在两端的“隐私与安全性”→“本地网络”中允许 DisplayWeave，并保持设备端 app 打开。",
            anchor: "Privacy_LocalNetwork"
        )
    }
    }
    @ViewBuilder private var diagnosticControls: some View {
    Toggle("发送诊断统计", isOn: setting(\.enableDebugStats))

#if DEBUG
    DisclosureGroup("短时测试（实验性）") {
        Picker("场景", selection: $benchmarkScene) {
            ForEach(BenchmarkScene.allCases, id: \.self) { scene in
                Text(scene.label).tag(scene)
            }
        }
        Picker("时长", selection: $benchmarkDuration) {
            ForEach(BenchmarkDuration.allCases, id: \.self) { duration in
                Text(duration.label).tag(duration)
            }
        }
        HStack {
            Button("开始（预热 30 秒）") {
                controller.startBenchmark(
                    scene: benchmarkScene, duration: benchmarkDuration)
            }
            .disabled(controller.sessions.count != 1)
            Button("停止") { controller.stopBenchmark() }
                .disabled(controller.sessions.isEmpty)
        }
        if let session = controller.sessions.first {
            Text(session.benchmarkStatus)
                .font(.caption.monospaced())
                .textSelection(.enabled)
        } else {
            Text("录制前请连接且仅连接一个接收端。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        Text("开发预览：记录实际 CSV/JSONL 样本；需要手动操作测试场景。")
            .font(.caption)
            .foregroundStyle(.secondary)
    }
#endif

    }
    @ViewBuilder
    private func permissionRow(_ title: String, granted: Bool, uncertain: Bool = false,
                               help: String, anchor: String,
                               request: (() -> Void)? = nil) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Image(systemName: uncertain ? "questionmark.circle.fill"
                            : granted ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(uncertain ? .orange : granted ? .green : .red)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(uncertain ? "待检查" : granted ? "已允许" : "未允许").font(.caption).foregroundStyle(.secondary)
                if uncertain || !granted {
                    Text(help)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if uncertain || !granted {
                if let request {
                    Button("授权…") { request() }
                        .controlSize(.small)
                        .help("向 macOS 请求此权限。如果系统弹窗之前已被关闭，这会把 app 注册到系统设置里的对应权限项，请在那里打开开关。")
                }
                Button("打开设置") {
                    PermissionMonitor.openPrivacyPane(anchor)
                }
                .controlSize(.small)
            }
        }
    }
}

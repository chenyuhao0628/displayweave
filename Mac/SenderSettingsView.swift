import SwiftUI

/// Presentation-only bindings; sender pipeline ownership stays in SenderController.
struct SenderSettingsView: View {
    @ObservedObject var controller: SenderController
    @StateObject private var permissions = PermissionMonitor()
    @State private var benchmarkScene = BenchmarkScene.staticDesktop
    @State private var benchmarkDuration = BenchmarkDuration.standard
    private var bitratePresets: [BitratePreset] {
        let codec: StreamCodec = controller.settings.codecMode == .h264 ? .h264 : .hevc
        let transport: BitrateTransport = controller.settings.transportMode == .wifi ? .wifi : .usb
        return StreamEncodingPolicy.availablePresets(
            mode: controller.settings.bitrateMode, codec: codec, transport: transport)
    }

    var body: some View {
        TabView {
            Form { Section("画质与带宽") { streamControls } }
                .tabItem { Label("串流", systemImage: "slider.horizontal.3") }
            Form { connectionControls; generalControls }
                .tabItem { Label("通用", systemImage: "gearshape") }
            Form { permissionControls; Section("诊断") { diagnosticControls } }
                .tabItem { Label("权限与诊断", systemImage: "checkmark.shield") }
        }
        .formStyle(.grouped)
        .padding(12)
        .frame(minWidth: 540, minHeight: 520)
    }

    @ViewBuilder private var streamControls: some View {
    VStack(alignment: .leading, spacing: 4) {
        Picker("帧率", selection: $controller.settings.fpsMode) {
            ForEach(StreamFpsMode.allCases, id: \.self) { mode in
                Text(mode.label).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .onChange(of: controller.settings.fpsMode) { _, _ in controller.restartAll() }
        Text("自动选择接收设备支持的帧率；Mac 接收最高 60 fps。实际帧率取决于设备与网络。")
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    VStack(alignment: .leading, spacing: 4) {
        Picker("编码", selection: $controller.settings.codecMode) {
            ForEach(StreamCodecMode.allCases, id: \.self) { mode in
                Text(mode.label).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .onChange(of: controller.settings.codecMode) { _, _ in controller.restartAll() }
        Text("自动选择双方支持的编码；HEVC 初始化失败时回退 H.264。")
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    VStack(alignment: .leading, spacing: 4) {
        Picker("画质", selection: $controller.settings.quality) {
            ForEach(StreamQuality.allCases, id: \.self) { q in
                Text(q.label).tag(q)
            }
        }
        .onChange(of: controller.settings.quality) { _, _ in controller.restartAll() }
        Text(controller.settings.quality.explanation)
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    VStack(alignment: .leading, spacing: 4) {
        Picker("码率", selection: $controller.settings.bitrateMode) {
            ForEach(BitrateMode.allCases, id: \.self) { mode in
                Text(mode.label).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .onChange(of: controller.settings.bitrateMode) { _, _ in
            if let first = bitratePresets.first,
               !bitratePresets.contains(controller.settings.bitratePreset) {
                controller.settings.bitratePreset = first
            }
            controller.restartAll()
        }
        if controller.settings.bitrateMode != .auto {
            Picker("目标码率", selection: $controller.settings.bitratePreset) {
                ForEach(bitratePresets, id: \.self) { preset in
                    Text(preset.label).tag(preset)
                }
            }
            .onChange(of: controller.settings.bitratePreset) { _, _ in
                controller.restartAll()
            }
        }
        if controller.settings.bitrateMode == .benchmark {
            Text("实验模式：可能增加延迟和排队，仅用于本地测试。")
                .font(.caption)
                .foregroundStyle(.orange)
        } else if controller.settings.bitrateMode == .auto {
            Text("自动根据排队、丢帧、往返时延和帧龄调整目标码率。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    }
    @ViewBuilder private var connectionControls: some View {
    VStack(alignment: .leading, spacing: 4) {
        Picker("连接方式", selection: $controller.settings.transportMode) {
            ForEach(StreamTransportMode.allCases, id: \.self) { mode in
                Text(mode.label).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .onChange(of: controller.settings.transportMode) { _, _ in
            controller.restartAll()
        }
        Text("自动模式优先 USB；Android USB 不可用时尝试同一设备的局域网连接。")
            .font(.caption)
            .foregroundStyle(.secondary)
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
            help: "用于接收设备上的触摸和滚动输入。",
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
    Toggle("发送诊断统计", isOn: $controller.settings.enableDebugStats)
        .onChange(of: controller.settings.enableDebugStats) { _, _ in controller.restartAll() }

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

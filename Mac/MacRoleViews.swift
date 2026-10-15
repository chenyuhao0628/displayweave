import SwiftUI
import Sparkle

@MainActor
private final class SenderRoleService: MacRoleService {
    func start() { SenderController.shared.setRoleEnabled(true) }
    func stop(completion: (() -> Void)?) {
        let cleanup = SenderController.shared.setRoleEnabled(false)
        Task { await cleanup?.value; completion?() }
    }
}

extension MacReceiverController: MacRoleService {}

@MainActor
private enum MacRoleServices {
    static let receiver = MacReceiverController()
    static let controller = MacRoleController(
        initialRole: MacRole(rawValue: UserDefaults.standard.string(forKey: "macRole") ?? "") ?? .sender,
        sender: SenderRoleService(), receiver: receiver,
        persist: { UserDefaults.standard.set($0.rawValue, forKey: "macRole") })
}

extension MacRoleController {
    static var shared: MacRoleController { MacRoleServices.controller }
    var receiver: MacReceiverController { MacRoleServices.receiver }
}

/// The compact menu panel and resizable desktop window share state and controls.
struct MacRootView: View {
    @ObservedObject var controller: SenderController
    var updater: SPUStandardUpdaterController?
    var compact = false
    @ObservedObject private var roles = MacRoleController.shared

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 36, height: 36)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("DisplayWeave").font(.title2.bold())
                    Text(roles.role == .sender ? "将其他设备用作你的显示器" : "接收另一台 Mac 的桌面")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button { SettingsWindow.show() } label: { Image(systemName: "gearshape") }
                    .help("设置（⌘,）").accessibilityLabel("设置")
                    .keyboardShortcut(",", modifiers: .command)
            }.padding(20)
            Picker("此 Mac 的角色", selection: Binding(get: { roles.role }, set: { roles.select($0) })) {
                ForEach(MacRole.allCases, id: \.self) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented).padding(.horizontal, 20).padding(.bottom, 16)
            .disabled(roles.transitioning)
            Divider()
            if roles.transitioning {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("正在释放连接并切换角色…").foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if roles.role == .sender {
                SenderWorkspaceView(controller: controller)
            } else {
                MacReceiverPanel(controller: roles.receiver)
            }
            Divider()
            HStack {
                Text(roles.role == .sender ? "发送屏幕" : "接收屏幕")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                if let updater { CheckForUpdatesView(updater: updater) }
                Button("退出") { NSApp.terminate(nil) }
            }.controlSize(.small).padding(.horizontal, 20).padding(.vertical, 12)
        }
        .frame(width: compact ? 480 : nil, height: compact ? 640 : nil)
        .frame(minWidth: 480, minHeight: 440)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

private struct MacReceiverPanel: View {
    @ObservedObject var controller: MacReceiverController
    @ObservedObject private var receiver: StreamReceiver

    init(controller: MacReceiverController) {
        self.controller = controller
        _receiver = ObservedObject(wrappedValue: controller.receiver)
    }

    var body: some View {
        Form {
            Section {
                Label(receiver.status, systemImage: receiver.connected ? "checkmark.circle.fill" : "antenna.radiowaves.left.and.right")
                    .font(.headline)
                if receiver.connected {
                    Text("送入显示层：\(receiver.fps) fps · H.264")
                        .font(.caption.monospaced()).foregroundStyle(.secondary)
                }
                HStack {
                    Button(controller.enabled ? "停止接收" : "开始接收") {
                        if controller.enabled { controller.stop() } else { controller.start() }
                    }.buttonStyle(.borderedProminent)
                    if receiver.connected {
                        Button("显示画面") { controller.showVideo() }
                        Button("断开连接") { receiver.disconnect() }
                    }
                }
            } header: { Text("接收状态") }
            Section("显示选项") {
                TextField("设备名称", text: $controller.name)
                Picker("接收显示器", selection: $controller.selectedDisplayID) {
                    ForEach(controller.screens, id: \.self) { screen in
                        Text(screen.localizedName).tag(MacReceiverController.id(screen))
                    }
                }
                Toggle("全屏显示接收画面", isOn: $controller.fullscreen)
            }
            Section("连接帮助") {
                Label("两台 Mac 加入同一 Wi-Fi 或以太网。", systemImage: "1.circle")
                Label("在另一台 Mac 选择发送屏幕，再选择本机。", systemImage: "2.circle")
                Label("在发送端选择扩展或镜像，并使用发送端键盘鼠标操作。", systemImage: "3.circle")
                Text("关闭接收画面窗口会断开当前连接。接收不需要屏幕录制或辅助功能权限。找不到设备时，请检查两端本地网络权限、防火墙与路由器隔离设置。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section {
                Text("仅在可信局域网开启：当前连接未加密，也无配对认证。开启后局域网内的发送端可以连接，每次仅接收一个发送端。")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }.formStyle(.grouped)
    }
}

struct MacConnectionIcon: View {
    @ObservedObject var sender: SenderController
    @ObservedObject private var receiver = MacRoleController.shared.receiver.receiver

    var body: some View {
        Image(systemName: sender.running || receiver.connected
              ? "rectangle.on.rectangle.fill" : "rectangle.on.rectangle")
    }
}

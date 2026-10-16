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
                if compact { Button("打开窗口") { MainWindow.show() } }
                if let updater { CheckForUpdatesView(updater: updater) }
                Button("退出") { NSApp.terminate(nil) }
            }.controlSize(.small).padding(.horizontal, 20).padding(.vertical, 12)
        }
        .frame(width: compact ? 480 : nil, height: compact ? 640 : nil)
        .frame(minWidth: 480, minHeight: 440)
        .tint(.blue)
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

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

struct MacRootView: View {
    @ObservedObject var controller: SenderController
    var updater: SPUStandardUpdaterController?
    @ObservedObject private var roles = MacRoleController.shared

    var body: some View {
        VStack(spacing: 0) {
            Picker("此 Mac 的角色", selection: Binding(get: { roles.role }, set: { roles.select($0) })) {
                ForEach(MacRole.allCases, id: \.self) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented).padding(12).disabled(roles.transitioning)
            Divider()
            if roles.role == .sender {
                ContentView(controller: controller, updater: updater)
            } else {
                MacReceiverPanel(controller: roles.receiver, sender: controller, updater: updater)
            }
        }
        .frame(width: 440)
    }
}

private struct MacReceiverPanel: View {
    @ObservedObject var controller: MacReceiverController
    @ObservedObject var sender: SenderController
    @ObservedObject private var receiver: StreamReceiver
    var updater: SPUStandardUpdaterController?

    init(controller: MacReceiverController, sender: SenderController, updater: SPUStandardUpdaterController?) {
        self.controller = controller; self.sender = sender; self.updater = updater
        _receiver = ObservedObject(wrappedValue: controller.receiver)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label("将这台 Mac 用作显示器", systemImage: "desktopcomputer").font(.title2.bold())
            Text("两台 Mac 连接同一 Wi-Fi 或以太网。在另一台 Mac 的发送列表中选择本机，再选择扩展或镜像。")
                .foregroundStyle(.secondary)
            TextField("设备名称", text: $controller.name)
            Picker("接收显示器", selection: $controller.selectedDisplayID) {
                ForEach(controller.screens, id: \.self) { screen in
                    Text(screen.localizedName).tag(MacReceiverController.id(screen))
                }
            }
            Toggle("全屏显示接收画面", isOn: $controller.fullscreen)
            GroupBox {
                VStack(alignment: .leading, spacing: 6) {
                    Text(receiver.status).font(.headline)
                    if receiver.connected { Text("送入显示层：\(receiver.fps) fps · H.264").font(.caption) }
                    Text("使用发送端的键盘和鼠标操作桌面。关闭接收画面窗口会断开当前连接。")
                        .font(.caption).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, alignment: .leading).padding(4)
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
            Text("仅在可信局域网开启：当前连接未加密，也无配对认证。开启后，局域网内的发送端可以连接；每次仅接收一个发送端。")
                .font(.caption).foregroundStyle(.secondary)
            Text("找不到设备时，请允许本地网络访问和防火墙入站连接，并检查路由器是否隔离客户端。接收模式不需要屏幕录制或辅助功能权限。")
                .font(.caption).foregroundStyle(.secondary)
            Spacer(minLength: 0)
            HStack {
                Picker("显示方式", selection: $sender.presentation) {
                    ForEach(AppPresentation.allCases, id: \.self) { Text($0.label).tag($0) }
                }.frame(width: 190)
                Spacer()
                Button("检查更新") { updater?.checkForUpdates(nil) }
                Button("退出") { NSApp.terminate(nil) }
            }
        }.padding(20).frame(width: 440, height: 540)
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

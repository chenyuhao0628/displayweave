import SwiftUI

struct MacReceiverPanel: View {
    @ObservedObject var controller: MacReceiverController
    @ObservedObject private var receiver: StreamReceiver
    @AppStorage("insecureLegacyReceiver") private var legacy = false

    init(controller: MacReceiverController) {
        self.controller = controller
        _receiver = ObservedObject(wrappedValue: controller.receiver)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                WorkspaceSection(title: "接收状态", symbol: "arrow.down.left.video") {
                    Label(receiver.status, systemImage: receiver.connected ? "checkmark.circle" : "antenna.radiowaves.left.and.right")
                        .font(.title3.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
                    Text("在发送端的设备列表中选择“\(controller.name)”。")
                        .foregroundStyle(.secondary).textSelection(.enabled)
                    if receiver.connected {
                        Label(receiver.encrypted ? "已加密配对" : "OpenDisplay 兼容 · 未加密",
                              systemImage: receiver.encrypted ? "lock.shield" : "lock.open")
                        Text("送入显示层：\(receiver.fps) fps · \(receiver.codecLabel)")
                            .font(.caption).monospacedDigit().foregroundStyle(.secondary)
                        HStack {
                            Button("显示画面") { controller.showVideo() }.buttonStyle(.borderedProminent)
                            Button("断开连接") { receiver.disconnect() }
                        }
                    }
                    if controller.enabled {
                        Button("停止接收") { controller.stop() }
                    } else {
                        Button("开始接收") { controller.start() }.buttonStyle(.borderedProminent)
                    }
                    Divider()
                    ConnectionModeControl(receiving: true)
                }
                WorkspaceSection(title: "显示选项", symbol: "display") {
                    LabeledContent("设备名称") {
                        TextField("设备名称", text: $controller.name).textFieldStyle(.roundedBorder)
                            .accessibilityLabel("设备名称")
                    }
                    Picker("接收显示器", selection: $controller.selectedDisplayID) {
                        ForEach(controller.screens, id: \.self) { screen in
                            Text(screen.localizedName).tag(MacReceiverController.id(screen))
                        }
                    }
                    Toggle("全屏显示接收画面", isOn: $controller.fullscreen)
                    Text("作为扩展显示器使用时，建议全屏并在发送端选择“跟随接收屏幕”。窗口模式会缩放整个远端桌面；调传输画质不会改变桌面大小。")
                        .font(.caption).foregroundStyle(.secondary)
                    Text("关闭接收画面窗口会断开当前连接。接收画面不需要屏幕录制权限。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                WorkspaceSection(title: "键盘与鼠标", symbol: "keyboard") {
                    Toggle("从此 Mac 操作发送端", isOn: Binding(get: { receiver.inputForwarding }, set: { receiver.setInputForwarding($0) }))
                    Text(receiver.inputForwarding ? receiver.inputStatus : "键鼠回传已关闭")
                        .font(.callout).foregroundStyle(.secondary)
                    Text("仅适用于已加密配对的 DisplayWeave，双方需开启并授予发送端辅助功能权限。仅聚焦接收画面时回传；⌃⌥Esc 立即停止。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                DisclosureGroup("首次连接与排障") {
                    VStack(alignment: .leading, spacing: 16) {
                        ConnectionSetupGuide(macReceiver: true, legacy: legacy)
                        Text("找不到设备时，请检查两端本地网络权限、防火墙与路由器隔离。每次仅接收一个发送端。")
                            .font(.caption).foregroundStyle(.secondary)
                    }.padding(.top, 12)
                }
            }.padding(20).frame(maxWidth: 840).frame(maxWidth: .infinity)
        }
    }
}

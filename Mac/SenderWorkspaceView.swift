import SwiftUI

struct SenderWorkspaceView: View {
    @ObservedObject var controller: SenderController

    var body: some View {
        Form {
            Section {
                Picker("显示模式", selection: $controller.mode) {
                    Text("扩展").tag(CaptureMode.extend)
                    Text("镜像").tag(CaptureMode.mirror)
                }
                .pickerStyle(.segmented)
                .onChange(of: controller.mode) { _, _ in controller.restartAll() }
                Text(controller.mode == .extend ? "增加一块独立桌面，可在系统设置中排列显示器。" : "在接收设备上显示这台 Mac 的主屏幕。")
                    .font(.caption).foregroundStyle(.secondary)
                Picker("连接方式", selection: $controller.settings.transportMode) {
                    ForEach(StreamTransportMode.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                .onChange(of: controller.settings.transportMode) { _, _ in controller.restartAll() }
            } header: { Text("连接选项") }

            Section {
                if controller.replacingSessions {
                    ProgressView("正在应用设置，等待旧连接释放…")
                }
                if let status = controller.macLANStatus {
                    HStack {
                        Text(status).font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        if controller.macLANRecoveryActive {
                            Button("取消恢复") { controller.cancelMacLANRecovery() }
                        }
                    }
                }
                if controller.deviceEntries.isEmpty && !controller.replacingSessions {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("等待发现设备", systemImage: "antenna.radiowaves.left.and.right")
                            .font(.headline)
                        Text("在另一台 Mac 选择“接收屏幕”，或打开手机/平板接收端。两端加入同一局域网，手机/平板也可连接 USB。")
                        Text("找不到设备时，请检查本地网络权限、防火墙及路由器客户端隔离。")
                            .font(.caption).foregroundStyle(.secondary)
                        Button("检查权限与设置…") { SettingsWindow.show() }
                    }.padding(.vertical, 8)
                }
                ForEach(controller.deviceEntries) { entry in
                    if let session = controller.session(for: entry) {
                        SessionRow(title: entry.name, session: session, controller: controller)
                    } else {
                        HStack(spacing: 12) {
                            Image(systemName: "display").foregroundStyle(.secondary)
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(entry.name).font(.headline)
                                Text(entry.transportLabel).font(.caption).foregroundStyle(.secondary)
                                if let detail = entry.detail {
                                    Text(detail).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            Spacer(minLength: 12)
                            if let target = entry.preferredTarget(for: controller.settings.transportMode) {
                                Button("连接") { controller.connect(to: target, userInitiated: true) }
                                    .accessibilityLabel("连接 \(entry.name)")
                                    .disabled(controller.replacingSessions || controller.macLANRecoveryActive)
                            }
                        }.padding(.vertical, 4)
                    }
                }
            } header: {
                HStack {
                    Text("设备")
                    Spacer()
                    if controller.running || controller.macLANRecoveryActive {
                        Button("全部断开") { controller.disconnectAll() }
                    }
                }
            } footer: {
                Text("局域网连接未加密，也无配对认证；请仅在可信网络中使用。")
            }
        }
        .formStyle(.grouped)
    }
}

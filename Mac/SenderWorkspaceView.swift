import SwiftUI

struct SenderWorkspaceView: View {
    @ObservedObject var controller: SenderController

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                WorkspaceSection(title: "连接准备", symbol: "rectangle.on.rectangle") {
                    Picker("显示模式", selection: $controller.mode) {
                        Text("扩展桌面").tag(CaptureMode.extend)
                        Text("镜像屏幕").tag(CaptureMode.mirror)
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: controller.mode) { _, _ in controller.restartAll() }
                    Text(controller.mode == .extend ? "增加一块独立桌面，可在系统设置中排列显示器。" : "在接收设备上显示这台 Mac 的主屏幕。")
                        .font(.callout).foregroundStyle(.secondary)
                    Picker("连接方式", selection: $controller.settings.transportMode) {
                        ForEach(StreamTransportMode.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                    .onChange(of: controller.settings.transportMode) { _, _ in controller.restartAll() }
                    Divider()
                    ConnectionModeControl()
                }
                WorkspaceSection(title: "设备", symbol: "display.2", detail: "\(controller.deviceEntries.count) 台设备") {
                    if let status = controller.securityStatus {
                        Label(status, systemImage: "lock.trianglebadge.exclamationmark")
                            .font(.callout).fixedSize(horizontal: false, vertical: true)
                        Button("处理配对问题…") { SettingsWindow.show(tab: "security") }
                    }
                    if controller.replacingSessions {
                        ProgressView("正在应用设置，等待旧连接释放…")
                    }
                    if let status = controller.macLANStatus {
                        Text(status).font(.callout).foregroundStyle(.secondary)
                        if controller.macLANRecoveryActive {
                            Button("取消恢复") { controller.cancelMacLANRecovery() }
                        }
                    }
                    if controller.deviceEntries.isEmpty && !controller.replacingSessions {
                        VStack(alignment: .leading, spacing: 12) {
                            Label("等待发现设备", systemImage: "antenna.radiowaves.left.and.right").font(.headline)
                            Text("在另一台 Mac 选择接收屏幕，或打开手机/平板接收端。支持 DisplayWeave 与 OpenDisplay。")
                                .foregroundStyle(.secondary)
                            Button("检查权限…") { SettingsWindow.show(tab: "permissions") }
                        }.padding(.vertical, 8)
                    }
                    ForEach(controller.deviceEntries) { entry in
                        if let session = controller.session(for: entry) {
                            SessionRow(title: entry.name, session: session, controller: controller)
                        } else {
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: "display").font(.title2).foregroundStyle(.secondary)
                                    .accessibilityHidden(true)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(entry.name).font(.headline).fixedSize(horizontal: false, vertical: true)
                                    Text(entry.transportLabel).font(.caption).foregroundStyle(.secondary)
                                    if entry.preferredTarget(for: controller.settings.transportMode) == nil {
                                        Text("当前连接方式不可用，请选择自动或局域网。")
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                    if let detail = entry.detail {
                                        Text(detail).font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                                Spacer(minLength: 8)
                                if let target = entry.preferredTarget(for: controller.settings.transportMode) {
                                    Button("连接") { controller.connect(to: target, userInitiated: true) }
                                        .buttonStyle(.borderedProminent)
                                        .accessibilityLabel("连接 \(entry.name)")
                                        .disabled(controller.replacingSessions || controller.macLANRecoveryActive)
                                }
                            }.padding(.vertical, 4)
                        }
                        if entry.id != controller.deviceEntries.last?.id { Divider() }
                    }
                    if controller.running || controller.macLANRecoveryActive {
                        Divider()
                        Button("全部断开") { controller.disconnectAll() }
                    }
                }
                DisclosureGroup("首次连接与排障") {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("DisplayWeave：接收端生成邀请 → 本机导入 → 选择设备。OpenDisplay：上方选择兼容两种客户端 → 选择设备。")
                        Text("找不到设备时，检查两端本地网络权限、防火墙与路由器隔离；USB 连接请确认线缆和设备授权。")
                            .foregroundStyle(.secondary)
                    }.font(.callout).padding(.top, 12)
                }
            }.padding(20).frame(maxWidth: 840)
                .frame(maxWidth: .infinity)
        }
    }
}

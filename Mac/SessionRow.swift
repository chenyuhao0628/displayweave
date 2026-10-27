import SwiftUI

struct SessionRow: View {
    let title: String
    @ObservedObject var session: DeviceSession
    let controller: SenderController

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: session.failed ? "exclamationmark.triangle" : "display")
                    .font(.title2).foregroundStyle(session.failed ? .orange : .secondary)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.headline).fixedSize(horizontal: false, vertical: true)
                    Text(session.status).font(.callout).fixedSize(horizontal: false, vertical: true)
                    Label("\(session.transportLabel) · \(session.sender.encrypted ? "已加密配对" : "OpenDisplay 兼容 · 未加密")",
                          systemImage: session.sender.encrypted ? "lock.shield" : "lock.open")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            if !session.streamDescription.isEmpty {
                Text(session.streamDescription).font(.caption).monospacedDigit()
            }
            if session.targetMbps > 0 || session.mbps > 0 {
                Text("生效目标 \(String(format: "%.1f", session.targetMbps)) · 实际发送 \(String(format: "%.1f", session.mbps)) Mbps")
                    .font(.caption).monospacedDigit().foregroundStyle(.secondary)
            }
            if let explanation = session.streamLimitDescription {
                Label(explanation, systemImage: "info.circle")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if controller.mode == .extend {
                Picker("桌面大小", selection: Binding(
                    get: { controller.desktopResolution(for: session) },
                    set: { controller.setDesktopResolution($0, for: session) })) {
                    ForEach(DesktopResolution.allCases, id: \.self) {
                        Text($0.label(native: session.nativeDesktop)).tag($0)
                    }
                }
                .disabled(controller.replacingSessions || !DesktopResolutionPreferences.validIdentity(session.deviceID))
                .help("自动匹配参考发送端与接收端的屏幕数据。更改仅重连这台设备；编码画质不会改变桌面大小。")
                if let desktop = session.appliedDesktop {
                    Text(desktop.summary).font(.caption).monospacedDigit().foregroundStyle(.secondary)
                }
                if let note = session.desktopMatchNote {
                    Text(note).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                if session.receiverInfo?.isMacReceiver == true,
                   controller.desktopResolution(for: session) == .automatic {
                    Text("以接收端全屏为基础；窗口模式会缩放整个桌面。")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            HStack {
                if session.failed {
                    Button("重试") { controller.retry(session) }.buttonStyle(.borderedProminent)
                        .accessibilityLabel("重试连接 \(title)")
                    Button("权限与诊断…") { SettingsWindow.show(tab: "permissions") }
                }
                Spacer()
                Button("断开") { controller.disconnect(session) }.accessibilityLabel("断开 \(title)")
            }.controlSize(.small)
        }.padding(.vertical, 4)
    }
}

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
                .help("跟随接收屏幕可匹配接收端当前的桌面大小。更改仅重连这台设备；编码画质不会改变窗口大小。")
                if let desktop = session.desktopGeometry(controller.desktopResolution(for: session)) {
                    Text(desktop.summary).font(.caption).monospacedDigit().foregroundStyle(.secondary)
                }
                if session.receiverInfo?.isMacReceiver == true {
                    Text("跨屏窗口大小不一致时，选“跟随接收屏幕”，并在接收端全屏显示。想降低负载，请调画质或选帧率优先；窗口模式会把整个桌面缩放进接收窗口。")
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

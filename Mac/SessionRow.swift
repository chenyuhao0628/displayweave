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
            if session.targetMbps > 0 || session.mbps > 0 {
                Text("目标 \(String(format: "%.1f", session.targetMbps)) · 实际 \(String(format: "%.1f", session.mbps)) Mbps")
                    .font(.caption).monospacedDigit().foregroundStyle(.secondary)
            }
            if controller.mode == .extend {
                Picker("桌面像素", selection: Binding(
                    get: { controller.desktopResolution(for: session) },
                    set: { controller.setDesktopResolution($0, for: session) })) {
                    ForEach(DesktopResolution.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                .disabled(controller.replacingSessions || !DesktopResolutionPreferences.validIdentity(session.deviceID))
                .help("按设备保存；更改仅重连这台设备。Retina 逻辑点为像素的一半；竖屏自动交换宽高。")
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

import SwiftUI

/// One connected device: live status, throughput, reconnect + disconnect.
struct SessionRow: View {
    let title: String
    @ObservedObject var session: DeviceSession
    let controller: SenderController

    private var statusColor: Color {
        if session.status.hasPrefix("正在扩展") || session.status.hasPrefix("正在镜像")
            || session.status.hasPrefix("已连接") {
            return .green
        }
        if session.status.hasPrefix("失败") || session.status.contains("已停止") {
            return .red
        }
        return .orange
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Circle()
                .fill(statusColor)
                .frame(width: 9, height: 9)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text("\(session.transportLabel) · \(session.status)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            if session.targetMbps > 0 || session.mbps > 0 {
                Text("目标 \(String(format: "%.1f", session.targetMbps)) · 实际 \(String(format: "%.1f", session.mbps)) Mbps")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            if controller.mode == .extend {
                Picker("桌面像素", selection: Binding(
                    get: { controller.desktopResolution(for: session) },
                    set: { controller.setDesktopResolution($0, for: session) })) {
                    ForEach(DesktopResolution.allCases, id: \.self) { resolution in
                        Text(resolution.label).tag(resolution)
                    }
                }
                .controlSize(.small)
                .disabled(controller.replacingSessions || !DesktopResolutionPreferences.validIdentity(session.deviceID))
                .help("按设备保存；更改仅重连这台设备。Retina 逻辑点为像素的一半；竖屏自动交换宽高。编码画质和接收上限另行生效。")
            }

            }
            Spacer()
            if session.failed {
                Button("重试") { controller.retry(session) }
                    .controlSize(.small)
                    .help("重新启动失败的连接")
                    .accessibilityLabel("重试连接 \(title)")
            }
            Button("断开") { controller.disconnect(session) }
                .controlSize(.small)
        }
    }
}

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

import SwiftUI

/// Shared by Apple waiting and first-run screens; no network or permission side effects.
struct ConnectionSetupGuide: View {
    var macReceiver = false
    var legacy = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            step(1, "准备连接", macReceiver
                 ? "两台 Mac 加入同一 Wi-Fi 或以太网，在另一台 Mac 选择发送屏幕。"
                 : "在 Mac 打开 DisplayWeave 或 OpenDisplay，通过 USB 或同一局域网连接。")
            step(2, legacy ? "使用兼容连接" : "完成首次配对", legacy
                 ? "此接收端已启用 OpenDisplay 兼容，无需配对邀请；请使用可信网络。"
                 : "在本机生成配对邀请，复制到发送端的“安全与配对”。OpenDisplay 用户可先选择兼容模式。")
            step(3, "选择这台设备", "在 Mac 的设备列表中连接本机，选择扩展或镜像，并保持接收端打开。")
        }
    }

    private func step(_ number: Int, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)").font(.subheadline.bold()).monospacedDigit()
                .frame(width: 28, height: 28)
                .background(Color.accentColor.opacity(0.12), in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(detail).font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }.accessibilityElement(children: .combine)
    }
}

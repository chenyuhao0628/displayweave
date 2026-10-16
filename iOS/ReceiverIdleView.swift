import SwiftUI

struct IdleView: View {
    @ObservedObject var receiver: PhoneReceiver
    @Binding var showSettings: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(spacing: 16) {
                    Image("AppLogo").resizable().scaledToFit()
                        .frame(width: 64, height: 64).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("DisplayWeave").font(.title.bold())
                        Text("将这台 \(deviceKind) 用作显示器").foregroundStyle(.secondary)
                    }
                }
                Label(receiver.status, systemImage: receiver.connected ? "checkmark.circle.fill" : "antenna.radiowaves.left.and.right")
                    .font(.headline).foregroundStyle(.tint)
                    .accessibilityAddTraits(.updatesFrequently)
                VStack(alignment: .leading, spacing: 16) {
                    Text("从 Mac 开始连接").font(.headline)
                    Label("在 Mac 上打开 DisplayWeave，选择发送屏幕。", systemImage: "1.circle")
                    Label("连接 USB，或让两端加入同一局域网。", systemImage: "2.circle")
                    Label("打开本机设置生成配对邀请，复制到 Mac 的“安全与配对”。", systemImage: "3.circle")
                    Label("在 Mac 的设备列表中选择本机，并保持此 app 打开。", systemImage: "4.circle")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
                Button { showSettings = true } label: {
                    Label("设置与帮助", systemImage: "gearshape")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }.buttonStyle(.borderedProminent)
                Text("默认使用加密配对。旧版本需在设置中显式启用未加密兼容。串流时可点右上角设置，也可摇动设备打开设置。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            .frame(maxWidth: 520)
            .padding(24)
            .frame(maxWidth: .infinity)
        }
        .background(Color(.systemBackground))
    }
}

import SwiftUI

struct IdleView: View {
    @ObservedObject var receiver: PhoneReceiver
    @Binding var showSettings: Bool
    @AppStorage("deviceName") private var deviceName = UIDevice.current.name
    @ObservedObject private var security = AppleTransportSecurityModel.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(spacing: 12) {
                    Image("AppLogo").resizable().scaledToFit()
                        .frame(width: 48, height: 48).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("DisplayWeave").font(.title2.bold())
                        Text("让屏幕连接起来").font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                VStack(alignment: .leading, spacing: 12) {
                    Label(receiver.status, systemImage: receiver.connected ? "checkmark.circle" : "antenna.radiowaves.left.and.right")
                        .font(.headline).fixedSize(horizontal: false, vertical: true)
                    Text("在 Mac 上选择“\(deviceName.isEmpty ? "DisplayWeave" : deviceName)”。")
                        .foregroundStyle(.secondary)
                    Label(security.legacyReceiver ? "OpenDisplay 兼容 · 未加密" : "DisplayWeave · 加密配对",
                          systemImage: security.legacyReceiver ? "lock.open" : "lock.shield")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading).padding(20)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
                VStack(alignment: .leading, spacing: 12) {
                    Picker("连接客户端", selection: Binding(get: { security.legacyReceiver }, set: security.setLegacyReceiver)) {
                        Text("DisplayWeave 加密").tag(false)
                        Text("OpenDisplay 兼容").tag(true)
                    }.pickerStyle(.menu)
                    Text(security.legacyReceiver ? "兼容连接无需邀请，未加密；请使用可信网络。更改模式会断开当前连接。" : "使用 OpenDisplay 时，选择兼容连接即可。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 16) {
                    Text("从 Mac 开始连接").font(.headline)
                    ConnectionSetupGuide(legacy: security.legacyReceiver)
                }
                Text("连接时保持 app 打开。串流画面的右上角始终提供设置入口。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            .frame(maxWidth: 520).padding(24).frame(maxWidth: .infinity)
        }
        .safeAreaInset(edge: .bottom) {
            Button { showSettings = true } label: {
                Label("连接设置", systemImage: "slider.horizontal.3")
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .buttonStyle(.borderedProminent)
            .accessibilityLabel("配对与连接设置")
            .frame(maxWidth: 520).padding(16).frame(maxWidth: .infinity)
            .background(.regularMaterial)
        }
        .background(Color(.systemBackground)).tint(.blue)
    }
}

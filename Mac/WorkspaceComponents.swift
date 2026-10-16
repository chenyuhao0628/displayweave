import SwiftUI

/// Small presentation primitives; session and transport ownership stays in controllers.
struct WorkspaceSection<Content: View>: View {
    let title: String
    let symbol: String
    var detail: String? = nil
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Label(title, systemImage: symbol).font(.headline)
                Spacer(minLength: 8)
                if let detail { Text(detail).font(.caption).foregroundStyle(.secondary) }
            }
            VStack(alignment: .leading, spacing: 16) { content }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 16))
                .overlay { RoundedRectangle(cornerRadius: 16).strokeBorder(Color(nsColor: .separatorColor).opacity(0.5)) }
        }
    }
}

struct ConnectionModeControl: View {
    var receiving = false
    @ObservedObject private var security = AppleTransportSecurityModel.shared

    private var legacy: Binding<Bool> {
        Binding(get: { receiving ? security.legacyReceiver : security.legacySender },
                set: { if receiving { security.setLegacyReceiver($0) } else { security.setLegacySender($0) } })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("客户端兼容", selection: legacy) {
                Text("DisplayWeave 加密").tag(false)
                Text(receiving ? "OpenDisplay 兼容" : "兼容两种客户端").tag(true)
            }
            .pickerStyle(.menu)
            Text(legacy.wrappedValue
                 ? (receiving ? "接收 OpenDisplay 或旧版客户端，无需邀请；此模式未加密，请使用可信网络。更改模式会断开当前连接。"
                    : "OpenDisplay 无需配对即可连接；DisplayWeave 仍使用加密配对。未加密连接仅用于可信网络。")
                 : (receiving ? "在本机生成配对邀请，再复制到发送端导入。使用 OpenDisplay 时可在此切换兼容模式。"
                    : "首次连接先在接收端生成邀请，再在这台 Mac 导入。使用 OpenDisplay 时可在此切换兼容模式。"))
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Button(legacy.wrappedValue ? "配对与兼容设置…" : "安全与配对…") { SettingsWindow.show(tab: "security") }
        }
    }
}

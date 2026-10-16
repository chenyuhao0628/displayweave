import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

struct TransportSecuritySettings: View {
    var permitsSending = false
    @ObservedObject private var model = AppleTransportSecurityModel.shared
    @State private var importText = ""
    @State private var showReset = false
    private let refresh = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        Group {
            Section("安全与配对") {
                Label(model.legacyReceiver ? "接收：旧版兼容，未加密" : "接收：加密且需要配对",
                      systemImage: model.legacyReceiver ? "lock.open" : "lock.shield")
                if let error = model.error {
                    Text(error).foregroundStyle(.red).font(.callout)
                    Button("重新读取安全状态") { model.retry() }
                }
                Text("首次连接：在接收端生成邀请，通过可信渠道复制到发送端。邀请两分钟内有效，只能成功配对一次；配对后重连不需要邀请。")
                    .font(.caption).foregroundStyle(.secondary)
                if model.invitation.isEmpty {
                    Button("生成接收配对邀请") { model.openPairing() }
                        .disabled(model.legacyReceiver)
                } else {
                    Text("配对窗口已开启，请勿公开邀请。")
                    Text(model.invitation).font(.caption.monospaced()).textSelection(.enabled)
                        .lineLimit(4)
                    HStack {
                        Button("复制邀请") { copyInvitation() }
                        Button("关闭配对窗口") { model.closePairing() }
                    }
                }
                if permitsSending {
                    TextField("粘贴接收端 DW1. 配对邀请", text: $importText, axis: .vertical)
                        .lineLimit(2...4)
                        .onChange(of: importText) { _, value in
                            if value.utf8.count > SecurePairingProtocol.maximumInvitationBytes {
                                importText = String(value.prefix(SecurePairingProtocol.maximumInvitationBytes))
                            }
                        }
                    Button("导入邀请") { model.importInvitation(importText); importText = "" }
                        .disabled(importText.isEmpty)
                    if let id = model.importedID {
                        Text("邀请已导入（\(id)），现在返回设备列表选择对应接收端。")
                            .font(.caption).textSelection(.enabled)
                        Button("清除待配对邀请") { model.clearImport() }
                    }
                }
            }
            Section("已配对设备") {
                if model.peers.isEmpty { Text("尚无配对记录").foregroundStyle(.secondary) }
                ForEach(model.peers) { peer in
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(peer.name.isEmpty ? peer.installID : peer.name)
                            Text(peer.revoked ? "已撤销，需要新邀请" : "已信任")
                                .font(.caption).foregroundStyle(.secondary)
                            Text(peer.certificateSHA256).font(.caption2.monospaced())
                                .textSelection(.enabled).lineLimit(2)
                        }
                        Spacer()
                        if !peer.revoked { Button("撤销", role: .destructive) { model.revoke(peer.installID) } }
                    }
                }
                Text("撤销会断开该设备，保留拒绝明文降级所需的历史。设备证书变化时，先撤销旧配对，再获取新邀请。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("兼容与恢复") {
                Toggle("接收旧版发送端（未加密）", isOn: Binding(get: { model.legacyReceiver }, set: model.setLegacyReceiver))
                if permitsSending {
                    Toggle("允许连接旧版接收端（未加密）", isOn: Binding(get: { model.legacySender }, set: model.setLegacySender))
                }
                Text("旧版兼容仅用于可信网络，切换会断开相关连接。曾经配对的设备不能降级到明文，TLS 错误也不会自动回退。")
                    .font(.caption).foregroundStyle(.secondary)
                DisclosureGroup("本机身份") {
                    Text(model.fingerprint).font(.caption.monospaced()).textSelection(.enabled)
                    Text("证书有效期一年。证书过期、密钥丢失或设备身份变化时，可重置后在两端撤销旧配对并重新生成邀请。")
                        .font(.caption).foregroundStyle(.secondary)
                    Button("重置本机传输身份…", role: .destructive) { showReset = true }
                }
            }
        }
        .onAppear { model.refresh() }
        .onReceive(refresh) { _ in model.refresh() }
        .confirmationDialog("重置将断开所有连接，并撤销本机全部配对。之后需要在两端重新配对。", isPresented: $showReset) {
            Button("重置传输身份", role: .destructive) { model.resetIdentity() }
            Button("取消", role: .cancel) { }
        }
    }

    private func copyInvitation() {
        guard !model.invitation.isEmpty else { return }
#if os(macOS)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents(); pasteboard.setString(model.invitation, forType: .string)
        let change = pasteboard.changeCount
        DispatchQueue.main.asyncAfter(deadline: .now() + 120) {
            if pasteboard.changeCount == change { pasteboard.clearContents() }
        }
#else
        UIPasteboard.general.setItems([[UIPasteboard.typeAutomatic: model.invitation]],
                                      options: [.localOnly: true, .expirationDate: Date().addingTimeInterval(120)])
#endif
    }
}

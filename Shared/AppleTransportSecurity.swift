import Foundation
import Combine

enum TransportInstallIdentity {
    static let value: String = {
        if let id = UserDefaults.standard.string(forKey: "installID") { return id }
        let id = UUID().uuidString
        UserDefaults.standard.set(id, forKey: "installID")
        return id
    }()
}

enum AppleReceiverSecurity {
    case tls(AppleTransportIdentity, SecurePairingState)
    case legacy

    static func live(localID: String) throws -> AppleReceiverSecurity {
        if UserDefaults.standard.bool(forKey: "insecureLegacyReceiver") { return .legacy }
        let context = try AppleSecurityStore.shared.context(localID: localID)
        return .tls(context.identity, context.pairing)
    }
    var encrypted: Bool { if case .tls = self { return true }; return false }
}

enum TransportSecurityChange {
    static let notification = Notification.Name("DisplayWeaveTransportSecurityChanged")
    static func post(_ kind: String, peer: String? = nil) {
        var info = ["kind": kind]
        info["peer"] = peer
        NotificationCenter.default.post(name: notification, object: nil, userInfo: info)
    }
}

/// A session freezes its security mode and receiver pin. Reconnect cannot
/// reinterpret a changed Bonjour TXT record as permission to downgrade.
final class AppleSenderSecurityPlan {
    let identity: AppleTransportIdentity
    let pairing: SecurePairingState
    let receiverID: String?
    let fingerprint: String?
    let receiverName: String
    private let invitationToken: Data?
    private let initialRevision: UInt64
    private var authenticated = false // sender's serial connection queue
    var encrypted: Bool { fingerprint != nil }

    private init(identity: AppleTransportIdentity, pairing: SecurePairingState,
                 receiverID: String?, fingerprint: String?, name: String, token: Data?) {
        self.identity = identity; self.pairing = pairing; self.receiverID = receiverID
        self.fingerprint = fingerprint; receiverName = name; invitationToken = token
        initialRevision = pairing.revision
    }

    static func resolve(identity: AppleTransportIdentity, pairing: SecurePairingState,
                        receiverID: String?, advertisedTLS: Bool, name: String,
                        invitation: PairingInvitation?, allowLegacy: Bool) throws -> AppleSenderSecurityPlan {
        let name = safeName(name)
        if let invitation, receiverID == nil || receiverID == invitation.receiverID {
            guard invitation.receiverID != pairing.localID else { throw TransportSecurityError.failed("请选择另一台设备的邀请") }
            if let peer = pairing.trustedPeer(invitation.receiverID), peer.certificateSHA256 != invitation.certificateSHA256 {
                throw TransportSecurityError.failed("设备证书已改变，请先撤销旧配对再导入新邀请")
            }
            return .init(identity: identity, pairing: pairing, receiverID: invitation.receiverID,
                         fingerprint: invitation.certificateSHA256, name: name, token: invitation.token)
        }
        if let receiverID, let peer = pairing.trustedPeer(receiverID) {
            return .init(identity: identity, pairing: pairing, receiverID: receiverID,
                         fingerprint: peer.certificateSHA256, name: name, token: nil)
        }
        guard !advertisedTLS, allowLegacy,
              receiverID.map({ !pairing.hasPairingHistory($0) }) ?? true else {
            throw TransportSecurityError.failed("请在接收端开启配对，将邀请粘贴到本机“设置 → 安全与配对”，再连接此设备")
        }
        return .init(identity: identity, pairing: pairing, receiverID: receiverID, fingerprint: nil, name: name, token: nil)
    }

    func admission(localName: String) throws -> SecureClientAdmission {
        guard let receiverID, let fingerprint else { throw TransportSecurityError.failed("此连接使用旧版兼容模式") }
        if authenticated {
            guard pairing.trustedPeer(receiverID)?.certificateSHA256 == fingerprint else {
                throw TransportSecurityError.failed("配对已撤销，请重新配对")
            }
        } else {
            guard pairing.revision == initialRevision else { throw TransportSecurityError.failed("配对设置已改变，请重新连接") }
        }
        return .init(pairing: pairing, receiverID: receiverID, receiverName: receiverName,
                     fingerprint: fingerprint, token: authenticated ? nil : invitationToken, localName: Self.safeName(localName))
    }

    func didAuthenticate() { authenticated = true }

    func permitsHello(id: String?) -> Bool {
        // Pre-install-ID OpenDisplay receivers are valid only when the user
        // explicitly enabled legacy and discovery did not promise an identity.
        // A pinned/advertised identity must never disappear to bypass trust.
        if id == nil {
            return fingerprint == nil && receiverID == nil && pairing.permitsAnonymousLegacy
        }
        guard let id, SecurePairingProtocol.validID(id), id != pairing.localID else { return false }
        if let receiverID, id != receiverID { return false }
        if let fingerprint { return authenticated && pairing.trustedPeer(id)?.certificateSHA256 == fingerprint }
        return !pairing.hasPairingHistory(id)
    }

    static func safeName(_ value: String) -> String {
        var result = ""
        for scalar in value.unicodeScalars where scalar.value >= 32 && scalar.value != 127 {
            let part = String(scalar)
            if result.utf8.count + part.utf8.count > 128 { break }
            result += part
        }
        return result
    }
}

/// UI state contains invitations only in memory. Network policy owns all trust;
/// no invitation token is written to defaults, discovery, logs or diagnostics.
@MainActor final class AppleTransportSecurityModel: ObservableObject {
    static let shared = AppleTransportSecurityModel()
    static let localID = TransportInstallIdentity.value
    @Published private(set) var invitation = ""
    @Published private(set) var importedID: String?
    @Published private(set) var peers: [SecurePeerRecord] = []
    @Published private(set) var fingerprint = ""
    @Published private(set) var error: String?
    @Published private(set) var legacyReceiver = UserDefaults.standard.bool(forKey: "insecureLegacyReceiver")
    @Published private(set) var legacySender = UserDefaults.standard.bool(forKey: "insecureLegacySender")
    private var imported: PairingInvitation?
    private var importedAt: Double = 0

    func refresh() {
        do {
            let state = try AppleSecurityStore.shared.pairingState(localID: Self.localID)
            peers = state.peers; fingerprint = state.localFingerprint
            if !state.pairingOpen { invitation = "" }
            if ProcessInfo.processInfo.systemUptime - importedAt >= 120 { clearImport() }
        } catch { self.error = error.localizedDescription }
    }
    func retry() {
        error = nil; refresh()
        if error == nil { TransportSecurityChange.post("listenerMode") }
    }
    func openPairing() {
        do {
            guard !legacyReceiver else { throw TransportSecurityError.failed("请先关闭接收端旧版兼容模式") }
            invitation = try AppleSecurityStore.shared.pairingState(localID: Self.localID).startPairing().encoded()
            error = nil; refresh()
        } catch { self.error = error.localizedDescription }
    }
    func closePairing() {
        try? AppleSecurityStore.shared.pairingState(localID: Self.localID).stopPairing()
        invitation = ""; TransportSecurityChange.post("pairingClosed")
    }
    func importInvitation(_ text: String) {
        do {
            let value = try PairingInvitation.decode(text)
            guard value.receiverID != Self.localID else { throw TransportSecurityError.failed("不能与本机配对，请复制另一台设备的邀请") }
            imported = value; importedID = value.receiverID
            importedAt = ProcessInfo.processInfo.systemUptime; error = nil
        } catch { self.error = error.localizedDescription }
    }
    func clearImport() { imported = nil; importedID = nil }
    func plan(receiverID: String?, advertisedTLS: Bool, name: String) throws -> AppleSenderSecurityPlan {
        refresh()
        let context = try AppleSecurityStore.shared.context(localID: Self.localID)
        return try .resolve(identity: context.identity,
            pairing: context.pairing, receiverID: receiverID,
            advertisedTLS: advertisedTLS, name: name, invitation: imported, allowLegacy: legacySender)
    }
    func revoke(_ id: String) {
        do {
            try AppleSecurityStore.shared.pairingState(localID: Self.localID).revoke(id)
            if importedID == id { clearImport() }
            invitation = ""; error = nil
            TransportSecurityChange.post("revoked", peer: id); refresh()
        } catch { self.error = error.localizedDescription }
    }
    func setLegacyReceiver(_ enabled: Bool) {
        closePairing()
        legacyReceiver = enabled
        UserDefaults.standard.set(enabled, forKey: "insecureLegacyReceiver")
        TransportSecurityChange.post("listenerMode")
    }
    func setLegacySender(_ enabled: Bool) {
        legacySender = enabled
        UserDefaults.standard.set(enabled, forKey: "insecureLegacySender")
        TransportSecurityChange.post("senderMode")
    }
    func resetIdentity() {
        closePairing(); clearImport()
        // Close sockets before even attempting a reset; a Keychain error must
        // not leave the old session operating under a misleading UI state.
        TransportSecurityChange.post("identityReset")
        do {
            try AppleSecurityStore.shared.resetIdentity(localID: Self.localID)
            error = nil; refresh()
            TransportSecurityChange.post("identityReset")
        } catch { self.error = error.localizedDescription }
    }
}

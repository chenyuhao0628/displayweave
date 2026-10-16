import Foundation

struct SecurePeerRecord: Codable, Equatable, Identifiable {
    let installID: String
    let name: String
    let certificateSHA256: String
    var revoked: Bool
    var id: String { installID }
}

/// Serializes trust and pairing admission across TLS callbacks and UI actions.
/// Persistence must succeed before any new identity is considered authorized.
final class SecurePairingState: @unchecked Sendable {
    let localID: String
    let localFingerprint: String
    private struct StoredTrust: Codable { let version: Int; let peers: [SecurePeerRecord] }
    private struct Window { let token: Data; let began: Double; let expires: Double; var failures = 0 }
    private let lock = NSLock()
    private var records: [String: SecurePeerRecord]
    private var window: Window?
    private let now: () -> Double
    private let persist: (Data) throws -> Void

    init(localID: String, localFingerprint: String, persisted: Data?,
         now: @escaping () -> Double = { ProcessInfo.processInfo.systemUptime },
         persist: @escaping (Data) throws -> Void) throws {
        guard SecurePairingProtocol.validID(localID), SecurePairingProtocol.fingerprintBytes(localFingerprint) != nil else {
            throw TransportSecurityError.failed("本机配对身份无效")
        }
        self.localID = localID; self.localFingerprint = localFingerprint
        self.now = now; self.persist = persist
        var records: [String: SecurePeerRecord] = [:]
        if let persisted {
            guard persisted.count <= 128 * 1024 else { throw TransportSecurityError.failed("配对记录过大") }
            let state = try JSONDecoder().decode(StoredTrust.self, from: persisted)
            guard state.version == 1, state.peers.count <= 128 else { throw TransportSecurityError.failed("配对记录版本或数量无效") }
            var pins = Set<String>()
            for peer in state.peers {
                guard SecurePairingProtocol.validID(peer.installID), peer.installID != localID,
                      SecurePairingProtocol.validName(peer.name),
                      SecurePairingProtocol.fingerprintBytes(peer.certificateSHA256) != nil,
                      records[peer.installID] == nil, pins.insert(peer.certificateSHA256).inserted else {
                    throw TransportSecurityError.failed("配对记录损坏；请在安全设置中检查身份")
                }
                records[peer.installID] = peer
            }
        }
        self.records = records
    }

    var peers: [SecurePeerRecord] { lock.withLock { records.values.sorted { $0.installID < $1.installID } } }
    var pairingOpen: Bool { lock.withLock { openWindow() != nil } }
    func hasPairingHistory(_ id: String) -> Bool { lock.withLock { records[id] != nil } }
    func trustedPeer(_ id: String) -> SecurePeerRecord? {
        lock.withLock { records[id].flatMap { $0.revoked ? nil : $0 } }
    }
    func acceptsTLS(_ fingerprint: String) -> Bool {
        lock.withLock {
            guard SecurePairingProtocol.fingerprintBytes(fingerprint) != nil else { return false }
            return records.values.contains { !$0.revoked && $0.certificateSHA256 == fingerprint } || openWindow() != nil
        }
    }

    func startPairing() throws -> PairingInvitation {
        try lock.withLock {
            let time = now()
            guard time.isFinite, time >= 0 else { throw TransportSecurityError.failed("单调时钟不可用") }
            let token = try SecurePairingProtocol.randomToken()
            window = Window(token: token, began: time, expires: time + 120)
            return PairingInvitation(receiverID: localID, certificateSHA256: localFingerprint, token: token)
        }
    }
    func stopPairing() { lock.withLock { window = nil } }

    func authenticate(_ request: SecureAuthRequest, fingerprint: String) throws -> SecurePeerRecord {
        try lock.withLock {
            guard SecurePairingProtocol.validID(request.installID), request.installID != localID,
                  SecurePairingProtocol.validName(request.name),
                  SecurePairingProtocol.fingerprintBytes(fingerprint) != nil else {
                throw TransportSecurityError.failed("无效的对端身份")
            }
            guard !records.values.contains(where: {
                $0.installID != request.installID && $0.certificateSHA256 == fingerprint
            }) else { throw TransportSecurityError.failed("同一证书不能冒用不同安装身份") }
            if let peer = records[request.installID], !peer.revoked {
                guard peer.certificateSHA256 == fingerprint else {
                    throw TransportSecurityError.failed("对端证书已改变；请先撤销旧配对，再从接收端获取新邀请")
                }
                return peer
            }
            guard let open = openWindow(), let token = request.pairingToken,
                  SecurePairingProtocol.equalToken(open.token, token) else {
                failToken()
                throw TransportSecurityError.failed("配对邀请无效或已过期；请从接收端获取新邀请")
            }
            let peer = try storePeer(id: request.installID, name: request.name, pin: fingerprint)
            window = nil
            return peer
        }
    }

    /// Called by a sender only after pinned TLS and a matching secureReady.
    func trustConfirmedReceiver(id: String, name: String, fingerprint: String,
                                explicitInvitation: Bool) throws {
        try lock.withLock {
            if let peer = records[id], !peer.revoked {
                guard peer.certificateSHA256 == fingerprint else { throw TransportSecurityError.failed("已配对证书不匹配") }
                return
            }
            guard explicitInvitation else { throw TransportSecurityError.failed("此设备需要新的配对邀请") }
            _ = try storePeer(id: id, name: name, pin: fingerprint)
        }
    }

    func revoke(_ id: String) throws {
        try lock.withLock {
            guard var peer = records[id] else { return }
            peer.revoked = true
            var next = records; next[id] = peer
            try commit(next)
            window = nil
        }
    }

    private func storePeer(id: String, name: String, pin: String) throws -> SecurePeerRecord {
        guard SecurePairingProtocol.validID(id), id != localID, SecurePairingProtocol.validName(name),
              SecurePairingProtocol.fingerprintBytes(pin) != nil,
              records[id] != nil || records.count < 128,
              !records.values.contains(where: { $0.installID != id && $0.certificateSHA256 == pin }) else {
            throw TransportSecurityError.failed("无法保存配对身份；记录无效或已达到 128 个身份上限")
        }
        let peer = SecurePeerRecord(installID: id, name: name, certificateSHA256: pin, revoked: false)
        var next = records; next[id] = peer
        try commit(next)
        return peer
    }
    private func commit(_ next: [String: SecurePeerRecord]) throws {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(StoredTrust(version: 1, peers: next.values.sorted { $0.installID < $1.installID }))
        guard data.count <= 128 * 1024 else { throw TransportSecurityError.failed("配对记录过大") }
        try persist(data)
        records = next
    }
    private func openWindow() -> Window? {
        let time = now()
        guard let window, time.isFinite, time >= window.began, time < window.expires, window.failures < 5 else {
            self.window = nil
            return nil
        }
        return window
    }
    private func failToken() {
        guard openWindow() != nil else { return }
        window?.failures += 1
        if window!.failures >= 5 { window = nil }
    }
}

import Foundation
import Security

/// App-scoped Keychain persistence. Never falls back to preferences or files.
final class AppleSecurityStore: @unchecked Sendable {
    static let shared = AppleSecurityStore(scope: Bundle.main.bundleIdentifier ?? "displayweave.unbundled")
    private let service: String
    private let keyTag: Data
    private let lock = NSLock()
    private var cached: AppleTransportIdentity?
    private var cachedState: SecurePairingState?

    // The ad-hoc macOS preview has no provisioned keychain access group.
    // Choose the login Keychain explicitly on macOS; iOS uses its sandboxed
    // data-protection Keychain. Never fall back to plaintext storage on error.
    static var storageAttributes: [CFString: Any] {
#if os(macOS)
        [:]
#else
        [kSecUseDataProtectionKeychain: true]
#endif
    }
    private static var protectionAttributes: [CFString: Any] {
#if os(macOS)
        [:]
#else
        [kSecAttrAccessible: kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
#endif
    }

    init(scope: String) {
        service = "\(scope).transport-security.v1"
        keyTag = Data("\(service).private-key".utf8)
    }

    func identity() throws -> AppleTransportIdentity {
        try lock.withLock { try identityLocked() }
    }

    private func identityLocked() throws -> AppleTransportIdentity {
            if let cached { return cached }
            let certificate = try load(account: "certificate")
            var result: CFTypeRef?
            let status = SecItemCopyMatching(keyQuery.merging([kSecReturnRef: true]) { _, new in new } as CFDictionary, &result)
            if status == errSecSuccess {
                guard let certificate, let result, CFGetTypeID(result) == SecKeyGetTypeID() else {
                    throw TransportSecurityError.failed("本机身份不完整；请显式重置身份并重新配对")
                }
                let identity = try AppleTransportIdentity.make(key: result as! SecKey, certificate: certificate)
                cached = identity
                return identity
            }
            guard status == errSecItemNotFound, certificate == nil else {
                throw TransportSecurityError.failed("无法读取本机身份（\(status)）；请解锁钥匙串后重试")
            }
            guard try load(account: "peers") == nil else {
                throw TransportSecurityError.failed("已配对身份的密钥丢失；请显式重置身份并重新配对")
            }
            return try createIdentity()
    }

    /// Explicit local action only. Tombstones survive identity rotation; a
    /// stale state object cannot save trust after this call starts rotating.
    func resetIdentity(localID: String) throws {
        try lock.withLock {
            let state = try cachedState ?? SecurePairingState(localID: localID,
                localFingerprint: String(repeating: "0", count: 64), persisted: load(account: "peers"),
                persist: { [self] in try save($0, account: "peers") })
            try state.revokeAllAndInvalidate()
            cachedState = nil; cached = nil
            for item in [keyQuery, query("certificate")] {
                let status = SecItemDelete(item as CFDictionary)
                guard status == errSecSuccess || status == errSecItemNotFound else {
                    throw TransportSecurityError.failed("无法重置钥匙串（\(status)）；请解锁后重试")
                }
            }
            _ = try createIdentity()
        }
    }

    private func createIdentity() throws -> AppleTransportIdentity {
            var error: Unmanaged<CFError>?
            let privateAttributes: [CFString: Any] = [kSecAttrIsPermanent: true, kSecAttrApplicationTag: keyTag,
                                                      kSecAttrIsExtractable: false]
                .merging(Self.protectionAttributes) { _, new in new }
            let attributes: [CFString: Any] = [
                kSecAttrKeyType: kSecAttrKeyTypeECSECPrimeRandom,
                kSecAttrKeySizeInBits: 256,
                kSecPrivateKeyAttrs: privateAttributes
            ].merging(Self.storageAttributes) { _, new in new }
            guard let key = SecKeyCreateRandomKey(attributes as CFDictionary, &error) else {
                let code = error.map { CFErrorGetCode($0.takeRetainedValue()) } ?? 0
                throw TransportSecurityError.failed("无法在钥匙串中创建本机身份（\(code)）；请检查应用签名并解锁钥匙串后重试")
            }
            do {
                let identity = try AppleTransportIdentity.make(key: key)
                try save(identity.certificateDER, account: "certificate")
                cached = identity
                return identity
            } catch {
                SecItemDelete(keyQuery as CFDictionary) // only this newly created app-scoped key
                throw error
            }
    }

    func pairingState(localID: String) throws -> SecurePairingState {
        try context(localID: localID).pairing
    }

    func context(localID: String) throws -> (identity: AppleTransportIdentity, pairing: SecurePairingState) {
        return try lock.withLock {
            let identity = try identityLocked()
            if let cachedState {
                guard cachedState.localID == localID else { throw TransportSecurityError.failed("安装身份发生变化，请重新配对") }
                return (identity, cachedState)
            }
            let state = try SecurePairingState(localID: localID, localFingerprint: identity.fingerprint,
                                               persisted: load(account: "peers"), persist: { [self] data in
                try save(data, account: "peers")
            })
            cachedState = state
            return (identity, state)
        }
    }

    private var keyQuery: [CFString: Any] {
        [kSecClass: kSecClassKey, kSecAttrKeyType: kSecAttrKeyTypeECSECPrimeRandom,
         kSecAttrApplicationTag: keyTag].merging(Self.storageAttributes) { _, new in new }
    }
    private func query(_ account: String) -> [CFString: Any] {
        [kSecClass: kSecClassGenericPassword, kSecAttrService: service, kSecAttrAccount: account,
         kSecAttrSynchronizable: false].merging(Self.storageAttributes) { _, new in new }
    }
    private func load(account: String) throws -> Data? {
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query(account).merging([kSecReturnData: true]) { _, new in new } as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data, data.count <= 128 * 1024 else {
            throw TransportSecurityError.failed("无法读取钥匙串（\(status)）；请解锁后重试")
        }
        return data
    }
    private func save(_ data: Data, account: String) throws {
        guard data.count <= 128 * 1024 else { throw TransportSecurityError.failed("安全记录过大") }
        let base = query(account)
        var status = SecItemUpdate(base as CFDictionary, [kSecValueData: data] as CFDictionary)
        if status == errSecItemNotFound {
            let values = [kSecValueData: data].merging(Self.protectionAttributes) { _, new in new }
            status = SecItemAdd(base.merging(values) { _, new in new } as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw TransportSecurityError.failed("无法保存钥匙串（\(status)）；请解锁后重试") }
    }
}

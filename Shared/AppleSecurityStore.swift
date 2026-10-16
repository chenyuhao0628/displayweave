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

    init(scope: String) {
        service = "\(scope).transport-security.v1"
        keyTag = Data("\(service).private-key".utf8)
    }

    func identity() throws -> AppleTransportIdentity {
        try lock.withLock {
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
            var error: Unmanaged<CFError>?
            guard let key = SecKeyCreateRandomKey([
                kSecAttrKeyType: kSecAttrKeyTypeECSECPrimeRandom,
                kSecAttrKeySizeInBits: 256,
                kSecUseDataProtectionKeychain: true,
                kSecPrivateKeyAttrs: [kSecAttrIsPermanent: true, kSecAttrApplicationTag: keyTag,
                                     kSecAttrAccessible: kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
            ] as CFDictionary, &error) else {
                throw TransportSecurityError.failed("无法在钥匙串中创建本机身份；请解锁后重试")
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
    }

    func pairingState(localID: String) throws -> SecurePairingState {
        let identity = try identity()
        return try lock.withLock {
            if let cachedState {
                guard cachedState.localID == localID else { throw TransportSecurityError.failed("安装身份发生变化，请重新配对") }
                return cachedState
            }
            let state = try SecurePairingState(localID: localID, localFingerprint: identity.fingerprint,
                                               persisted: load(account: "peers"), persist: { [self] data in
                try save(data, account: "peers")
            })
            cachedState = state
            return state
        }
    }

    private var keyQuery: [CFString: Any] {
        [kSecClass: kSecClassKey, kSecAttrKeyType: kSecAttrKeyTypeECSECPrimeRandom,
         kSecAttrApplicationTag: keyTag, kSecUseDataProtectionKeychain: true]
    }
    private func query(_ account: String) -> [CFString: Any] {
        [kSecClass: kSecClassGenericPassword, kSecAttrService: service, kSecAttrAccount: account,
         kSecUseDataProtectionKeychain: true, kSecAttrSynchronizable: false]
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
            status = SecItemAdd(base.merging([kSecValueData: data,
                kSecAttrAccessible: kSecAttrAccessibleWhenUnlockedThisDeviceOnly]) { _, new in new } as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw TransportSecurityError.failed("无法保存钥匙串（\(status)）；请解锁后重试") }
    }
}

import Foundation
import Security
import CryptoKit

enum TransportSecurityError: LocalizedError {
    case failed(String)
    var errorDescription: String? {
        if case .failed(let detail) = self { return "安全连接失败：\(detail)" }
        return nil
    }
}

/// A transport identity, separate from all application/update signing keys.
struct AppleTransportIdentity {
    let identity: SecIdentity
    let certificateDER: Data
    var fingerprint: String { Self.fingerprint(certificateDER) }

    static func fingerprint(_ certificate: Data) -> String {
        SHA256.hash(data: certificate).map { String(format: "%02x", $0) }.joined()
    }

    static func ephemeral() throws -> AppleTransportIdentity {
        var error: Unmanaged<CFError>?
        guard let key = SecKeyCreateRandomKey([
            kSecAttrKeyType: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeySizeInBits: 256
        ] as CFDictionary, &error) else {
            throw TransportSecurityError.failed("无法创建传输密钥")
        }
        return try make(key: key)
    }

    static func make(key: SecKey, certificate: Data? = nil) throws -> AppleTransportIdentity {
        let der = try certificate ?? TransportCertificateDER.create(key: key)
        guard der.count <= 8192, let cert = SecCertificateCreateWithData(nil, der as CFData),
              let identity = SecIdentityCreate(nil, cert, key) else {
            throw TransportSecurityError.failed("证书与本机密钥不匹配，请在安全设置中重置身份并重新配对")
        }
        return AppleTransportIdentity(identity: identity, certificateDER: der)
    }
}

/// Only encodes our small local X.509 certificate. Cryptographic generation and
/// signing are performed by Security; peer certificates use platform parsers.
private enum TransportCertificateDER {
    static func value(_ tag: UInt8, _ bytes: Data) -> Data {
        var result = Data([tag])
        if bytes.count < 128 { result.append(UInt8(bytes.count)) }
        else {
            var length = bytes.count, encoded: [UInt8] = []
            while length > 0 { encoded.insert(UInt8(length & 0xff), at: 0); length >>= 8 }
            result.append(0x80 | UInt8(encoded.count)); result.append(contentsOf: encoded)
        }
        result.append(bytes)
        return result
    }
    static func sequence(_ fields: Data...) -> Data { value(0x30, fields.reduce(Data(), +)) }
    static func oid(_ bytes: [UInt8]) -> Data { value(0x06, Data(bytes)) }
    static func integer(_ bytes: Data) -> Data {
        value(0x02, (bytes.first.map { $0 & 0x80 != 0 } ?? false) ? Data([0]) + bytes : bytes)
    }
    static func time(_ date: Date) -> Data {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy"
        let generalized = (Int(formatter.string(from: date)) ?? 2050) >= 2050
        formatter.dateFormat = generalized ? "yyyyMMddHHmmss'Z'" : "yyMMddHHmmss'Z'"
        return value(generalized ? 0x18 : 0x17, Data(formatter.string(from: date).utf8))
    }
    static func create(key: SecKey) throws -> Data {
        guard let publicKey = SecKeyCopyPublicKey(key),
              let external = SecKeyCopyExternalRepresentation(publicKey, nil) as Data?,
              external.count == 65, external.first == 4 else {
            throw TransportSecurityError.failed("不支持的传输公钥")
        }
        var serial = Data(count: 16)
        let randomStatus = serial.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, 16, $0.baseAddress!) }
        guard randomStatus == errSecSuccess else { throw TransportSecurityError.failed("系统随机源不可用") }
        // Positive, nonzero, at most 16 octets.
        serial[0] = (serial[0] & 0x7f) | 1
        let algorithm = sequence(oid([0x2a, 0x86, 0x48, 0xce, 0x3d, 0x04, 0x03, 0x02])) // ECDSA-SHA256
        let name = sequence(value(0x31, sequence(oid([0x55, 0x04, 0x03]),
                            value(0x0c, Data("DisplayWeave Transport".utf8)))))
        let spki = sequence(sequence(oid([0x2a, 0x86, 0x48, 0xce, 0x3d, 0x02, 0x01]),
                                     oid([0x2a, 0x86, 0x48, 0xce, 0x3d, 0x03, 0x01, 0x07])),
                            value(0x03, Data([0]) + external))
        let basicConstraints = sequence(oid([0x55, 0x1d, 0x13]), value(0x01, Data([0xff])),
                                        value(0x04, sequence()))
        let keyUsage = sequence(oid([0x55, 0x1d, 0x0f]), value(0x01, Data([0xff])),
                                value(0x04, value(0x03, Data([7, 0x80]))))
        let usage = sequence(oid([0x55, 0x1d, 0x25]), value(0x04, sequence(
            oid([0x2b, 0x06, 0x01, 0x05, 0x05, 0x07, 0x03, 0x01]),
            oid([0x2b, 0x06, 0x01, 0x05, 0x05, 0x07, 0x03, 0x02]))))
        let now = Date()
        let tbs = sequence(value(0xa0, integer(Data([2]))), integer(serial), algorithm, name,
                           sequence(time(now.addingTimeInterval(-86400)),
                                    time(now.addingTimeInterval(365 * 86400))), name, spki,
                           value(0xa3, sequence(basicConstraints, keyUsage, usage)))
        guard let signature = SecKeyCreateSignature(key, .ecdsaSignatureMessageX962SHA256,
                                                    tbs as CFData, nil) as Data? else {
            throw TransportSecurityError.failed("无法签署传输证书")
        }
        return sequence(tbs, algorithm, value(0x03, Data([0]) + signature))
    }
}

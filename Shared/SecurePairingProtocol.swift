import Foundation
import Security

enum SecurePairingProtocol {
    static let maximumInvitationBytes = 2048
    static let maximumAuthBytes = 4096
    static func validID(_ value: String) -> Bool {
        !value.isEmpty && value.utf8.count <= 256 && !value.unicodeScalars.contains { $0.value < 32 || $0.value == 127 }
    }
    static func validName(_ value: String) -> Bool {
        value.utf8.count <= 128 && !value.unicodeScalars.contains { $0.value < 32 || $0.value == 127 }
    }
    static func fingerprintBytes(_ value: String) -> Data? {
        guard value.utf8.count == 64, value.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }) else { return nil }
        let chars = Array(value.utf8)
        return Data(stride(from: 0, to: 64, by: 2).map { UInt8(String(bytes: chars[$0...$0 + 1], encoding: .utf8)!, radix: 16)! })
    }
    static func hex(_ value: Data) -> String { value.map { String(format: "%02x", $0) }.joined() }
    static func randomToken() throws -> Data {
        var data = Data(count: 32)
        guard data.withUnsafeMutableBytes({ SecRandomCopyBytes(kSecRandomDefault, 32, $0.baseAddress!) }) == errSecSuccess else {
            throw TransportSecurityError.failed("系统随机源不可用")
        }
        return data
    }
    static func equalToken(_ a: Data, _ b: Data) -> Bool {
        guard a.count == 32, b.count == 32 else { return false }
        return zip(a, b).reduce(UInt8(0)) { $0 | ($1.0 ^ $1.1) } == 0
    }
    static func appendString(_ string: String, to data: inout Data) {
        let bytes = Data(string.utf8)
        data.append(UInt8(bytes.count >> 8)); data.append(UInt8(bytes.count & 255)); data.append(bytes)
    }
    struct Reader {
        let data: Data
        var offset = 0
        mutating func take(_ count: Int) throws -> Data {
            guard count >= 0, count <= data.count - offset else { throw TransportSecurityError.failed("配对消息不完整") }
            defer { offset += count }
            return Data(data.dropFirst(offset).prefix(count))
        }
        mutating func string(maximum: Int) throws -> String {
            let size = try take(2), count = Int(size[0]) << 8 | Int(size[1])
            guard count <= maximum, let value = String(data: try take(count), encoding: .utf8) else {
                throw TransportSecurityError.failed("配对消息字符串无效")
            }
            return value
        }
        var finished: Bool { offset == data.count }
    }
}

struct PairingInvitation: Equatable {
    let receiverID: String
    let certificateSHA256: String
    let token: Data

    func encoded() throws -> String {
        guard SecurePairingProtocol.validID(receiverID),
              let pin = SecurePairingProtocol.fingerprintBytes(certificateSHA256), token.count == 32 else {
            throw TransportSecurityError.failed("配对邀请无效")
        }
        var bytes = Data("DWP1".utf8)
        SecurePairingProtocol.appendString(receiverID, to: &bytes)
        bytes.append(pin); bytes.append(token)
        return "DW1." + bytes.base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }

    static func decode(_ text: String) throws -> PairingInvitation {
        guard text.utf8.count <= SecurePairingProtocol.maximumInvitationBytes else {
            throw TransportSecurityError.failed("配对邀请过长，请重新复制接收端的邀请")
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("DW1.") else { throw TransportSecurityError.failed("不是 DisplayWeave 配对邀请") }
        let payload = String(trimmed.dropFirst(4))
        guard payload.utf8.allSatisfy({ (65...90).contains($0) || (97...122).contains($0)
            || (48...57).contains($0) || $0 == 45 || $0 == 95 }) else {
            throw TransportSecurityError.failed("配对邀请编码无效")
        }
        var base64 = payload.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
        guard let data = Data(base64Encoded: base64) else { throw TransportSecurityError.failed("配对邀请编码无效") }
        var reader = SecurePairingProtocol.Reader(data: data)
        guard try reader.take(4) == Data("DWP1".utf8) else { throw TransportSecurityError.failed("不支持此配对版本") }
        let id = try reader.string(maximum: 256)
        let pin = SecurePairingProtocol.hex(try reader.take(32)), token = try reader.take(32)
        guard reader.finished, SecurePairingProtocol.validID(id) else { throw TransportSecurityError.failed("配对邀请字段无效") }
        let invitation = PairingInvitation(receiverID: id, certificateSHA256: pin, token: token)
        guard try invitation.encoded() == trimmed else { throw TransportSecurityError.failed("配对邀请编码不规范") }
        return invitation
    }
}

struct SecureAuthRequest: Equatable {
    let installID: String
    let name: String
    let pairingToken: Data?
    func encoded() throws -> Data {
        guard SecurePairingProtocol.validID(installID), SecurePairingProtocol.validName(name),
              pairingToken == nil || pairingToken?.count == 32 else { throw TransportSecurityError.failed("认证字段无效") }
        var data = Data("DWA1".utf8)
        data.append(pairingToken == nil ? 0 : 1)
        SecurePairingProtocol.appendString(installID, to: &data)
        SecurePairingProtocol.appendString(name, to: &data)
        if let pairingToken { data.append(pairingToken) }
        return data
    }
    static func decode(_ data: Data) throws -> SecureAuthRequest {
        guard data.count <= SecurePairingProtocol.maximumAuthBytes else { throw TransportSecurityError.failed("认证消息过长") }
        var reader = SecurePairingProtocol.Reader(data: data)
        guard try reader.take(4) == Data("DWA1".utf8) else { throw TransportSecurityError.failed("认证前不接受应用数据") }
        let flags = try reader.take(1)[0]
        guard flags <= 1 else { throw TransportSecurityError.failed("认证标记无效") }
        let id = try reader.string(maximum: 256), name = try reader.string(maximum: 128)
        let token = flags == 1 ? try reader.take(32) : nil
        guard reader.finished, SecurePairingProtocol.validID(id), SecurePairingProtocol.validName(name) else {
            throw TransportSecurityError.failed("认证字段无效")
        }
        return SecureAuthRequest(installID: id, name: name, pairingToken: token)
    }
    static func ready(_ receiverID: String) throws -> Data {
        guard SecurePairingProtocol.validID(receiverID) else { throw TransportSecurityError.failed("接收端身份无效") }
        var data = Data("DWR1".utf8)
        SecurePairingProtocol.appendString(receiverID, to: &data)
        return data
    }
    static func readyIdentity(_ data: Data) throws -> String {
        guard data.count <= SecurePairingProtocol.maximumAuthBytes else { throw TransportSecurityError.failed("认证响应过长") }
        var reader = SecurePairingProtocol.Reader(data: data)
        guard try reader.take(4) == Data("DWR1".utf8) else { throw TransportSecurityError.failed("接收端未确认认证") }
        let id = try reader.string(maximum: 256)
        guard reader.finished, SecurePairingProtocol.validID(id) else { throw TransportSecurityError.failed("认证响应身份无效") }
        return id
    }
}

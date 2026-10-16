// Isolated transport probe only; no capture, input injection or installed identity.
import Foundation
import Network
import Security

@main enum SecureAndroidReceiverClient {
    static func main() throws {
        let folder = URL(fileURLWithPath: CommandLine.arguments[1])
        let port = NWEndpoint.Port(rawValue: UInt16(CommandLine.arguments[2])!)!
        let invitation = try PairingInvitation.decode(String(contentsOf: folder.appendingPathComponent("invitation.txt"), encoding: .utf8))
        let certificateData = try Data(contentsOf: folder.appendingPathComponent("server.der"))
        let certificate = SecCertificateCreateWithData(nil, certificateData as CFData)!
        var trust: SecTrust?
        precondition(SecTrustCreateWithCertificates(certificate, SecPolicyCreateSSL(true, nil), &trust) == errSecSuccess)
        if !AppleTLS.validate(trust!, server: true, acceptedFingerprint: { $0 == invitation.certificateSHA256 }) {
            var error: CFError?
            _ = SecTrustEvaluateWithError(trust!, &error)
            preconditionFailure("Android certificate validation failed: \(String(describing: error))")
        }
        print("Android Keystore certificate passed Apple SSL policy")
        let identity = try AppleTransportIdentity.ephemeral()
        let state = try SecurePairingState(localID: "test-sender", localFingerprint: identity.fingerprint,
                                           persisted: nil, persist: { _ in })
        let queue = DispatchQueue(label: "android.secure.runtime.test")
        let tls = try AppleTLS.options(identity: identity, peerIsServer: true, queue: queue) { $0 == invitation.certificateSHA256 }
        let connection = NWConnection(host: "127.0.0.1", port: port, using: NWParameters(tls: tls, tcp: .init()))
        defer { connection.cancel() }
        let done = DispatchSemaphore(value: 0)
        var success = false
        let admission = AppleSecureAdmission(connection: connection, queue: queue) { result in
            switch result {
            case .success: success = true
            case .failure(let error): fputs("Admission: \(error.localizedDescription)\n", stderr)
            }
            done.signal()
        }
        let plan = SecureClientAdmission(pairing: state, receiverID: invitation.receiverID,
                                        receiverName: "Android", fingerprint: invitation.certificateSHA256,
                                        token: invitation.token, localName: "Fixture Mac")
        queue.async { admission.startClient(plan) }
        let finished = done.wait(timeout: .now() + 15)
        withExtendedLifetime(admission) {}
        precondition(finished == .success && success, "Android TLS admission failed")
        func read(_ count: Int) -> Data? {
            let readDone = DispatchSemaphore(value: 0)
            var value: Data?
            connection.receive(minimumIncompleteLength: count, maximumLength: count) { data, _, ended, error in
                if error == nil, !ended, let data, data.count == count { value = data }
                readDone.signal()
            }
            precondition(readDone.wait(timeout: .now() + 60) == .success, "Android test socket timed out")
            return value
        }
        func message() throws -> [String: Any]? {
            guard let header = read(4) else { return nil }
            let length = header.reduce(0) { ($0 << 8) | Int($1) }
            precondition(length > 0 && length <= 64 * 1024)
            guard let data = read(length) else { return nil }
            return try JSONSerialization.jsonObject(with: data) as? [String: Any]
        }
        let hello = try message()
        precondition(hello?["type"] as? String == "hello" && hello?["id"] as? String == invitation.receiverID)
        precondition(hello?["device"] as? String == "Android")
        // A plaintext arrival must not replace the authenticated application.
        let stranger = NWConnection(host: "127.0.0.1", port: port, using: .tcp)
        stranger.start(queue: queue)
        defer { stranger.cancel() }
        func send(_ object: [String: Any]) throws {
            let data = try JSONSerialization.data(withJSONObject: object)
            connection.send(content: ReceiverFrameDecoder.frame(data), completion: .contentProcessed { _ in })
        }
        try send(["type": "ping", "t": 123.0])
        for _ in 0..<10 {
            guard let payload = try message() else { preconditionFailure("unauthorized candidate interrupted authenticated session") }
            if payload["type"] as? String == "pong" {
                try Data("ready".utf8).write(to: folder.appendingPathComponent("ready.txt"), options: .atomic)
                break
            }
        }
        precondition(FileManager.default.fileExists(atPath: folder.appendingPathComponent("ready.txt").path))
        // The runner revokes Fixture Mac through the real Settings UI.
        var closed = false
        for _ in 0..<60 {
            guard let payload = try message() else { closed = true; break }
            if payload["type"] as? String == "ping" { try send(["type": "pong", "t": payload["t"] ?? 0, "mt": 0]) }
        }
        precondition(closed, "revocation left Android socket open")
        print("Apple → Android Keystore TLS, matching application hello, plaintext isolation and live UI revocation PASS")
    }
}

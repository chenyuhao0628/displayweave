import Foundation
import Network
import AVFoundation

private final class SecureReceiverPeer {
    let queue = DispatchQueue(label: "secure.receiver.peer")
    let connection: NWConnection
    var admission: AppleSecureAdmission?
    init(port: UInt16, identity: AppleTransportIdentity, state: SecurePairingState,
         invitation: PairingInvitation) throws {
        let tls = try AppleTLS.options(identity: identity, peerIsServer: true, queue: queue,
                                       acceptedFingerprint: { $0 == invitation.certificateSHA256 })
        connection = NWConnection(host: "127.0.0.1", port: .init(rawValue: port)!, using: NWParameters(tls: tls, tcp: .init()))
        let done = DispatchSemaphore(value: 0)
        var accepted = false
        admission = AppleSecureAdmission(connection: connection, queue: queue) { result in
            if case .success = result { accepted = true }; done.signal()
        }
        let plan = SecureClientAdmission(pairing: state, receiverID: invitation.receiverID, receiverName: "Receiver",
                                         fingerprint: invitation.certificateSHA256, token: invitation.token, localName: "Sender")
        queue.async { self.admission?.startClient(plan) }
        precondition(done.wait(timeout: .now() + 5) == .success && accepted)
    }
    func read(_ count: Int) -> Data {
        let done = DispatchSemaphore(value: 0)
        var result = Data()
        connection.receive(minimumIncompleteLength: count, maximumLength: count) { data, _, _, error in
            if error == nil, let data { result = data }; done.signal()
        }
        precondition(done.wait(timeout: .now() + 3) == .success && result.count == count)
        return result
    }
    func hello() throws -> [String: Any] {
        let size = read(4).reduce(0) { ($0 << 8) | Int($1) }
        precondition(size > 0 && size <= 4096)
        return try JSONSerialization.jsonObject(with: read(size)) as! [String: Any]
    }
}

@main enum MacSecureReceiverSelfTest {
    @MainActor static func wait(_ description: String = "Mac state", seconds: Int = 5, _ predicate: () -> Bool) async throws {
        for _ in 0..<(seconds * 20) { if predicate() { return }; try await Task.sleep(for: .milliseconds(50)) }
        throw ReceiverTestFailure(message: "secure receiver state timed out: \(description)")
    }
    @MainActor static func main() async throws {
        if CommandLine.arguments.count == 4, CommandLine.arguments[1] == "--ios-fixture" {
            try await testPhone(folder: URL(fileURLWithPath: CommandLine.arguments[2]),
                                port: UInt16(CommandLine.arguments[3])!)
            return
        }
        let identity = try AppleTransportIdentity.ephemeral(), sender = try AppleTransportIdentity.ephemeral()
        let state = try SecurePairingState(localID: StreamReceiver.installID, localFingerprint: identity.fingerprint,
                                           persisted: nil, persist: { _ in })
        let senderState = try SecurePairingState(localID: "test-sender", localFingerprint: sender.fingerprint,
                                                 persisted: nil, persist: { _ in })
        let receiver = StreamReceiver(securityProvider: { .tls(identity, state) })
        receiver.start(port: 0, advertiseService: false)
        try await wait { receiver.listeningPort != 0 }
        let port = receiver.listeningPort
        let plain = NWConnection(host: "127.0.0.1", port: .init(rawValue: port)!, using: .tcp)
        plain.start(queue: .global())
        plain.send(content: ReceiverFrameDecoder.frame(Data("{\"type\":\"ping\"}".utf8)), completion: .contentProcessed { _ in })
        try await Task.sleep(for: .milliseconds(150))
        precondition(!receiver.connected, "plaintext reached receiver application")
        let invitation = try state.startPairing()
        let client = try await Task.detached {
            let client = try SecureReceiverPeer(port: port, identity: sender, state: senderState,
                                                invitation: invitation)
            let hello = try client.hello()
            precondition(hello["id"] as? String == invitation.receiverID)
            return client
        }.value
        try await wait { receiver.connected && receiver.encrypted }
        let frame = try await Task.detached { try receiverTestH264Frame() }.value
        let config = try JSONSerialization.data(withJSONObject: ["type": "streamConfig", "codec": "h264", "width": 64, "height": 64, "fps": 30])
        client.connection.send(content: ReceiverFrameDecoder.frame(config) + ReceiverFrameDecoder.frame(frame), completion: .contentProcessed { _ in })
        try await wait { receiver.videoSize == CGSize(width: 64, height: 64) }
        // An unauthenticated arrival cannot replace the live decoder/session.
        let stranger = NWConnection(host: "127.0.0.1", port: .init(rawValue: port)!, using: .tcp)
        stranger.start(queue: .global())
        try await Task.sleep(for: .milliseconds(150))
        precondition(receiver.connected && receiver.videoSize.width == 64)
        try state.revoke("test-sender")
        TransportSecurityChange.post("revoked", peer: "test-sender")
        try await wait { !receiver.connected && receiver.videoSize == .zero }
        receiver.stop()
        plain.cancel(); stranger.cancel(); client.connection.cancel()
        try await wait { receiver.listeningPort == 0 }
        print("Mac receiver: TLS before hello/video, plaintext rejection, active-session isolation and revocation PASS")
    }

    @MainActor private static func testPhone(folder: URL, port: UInt16) async throws {
        func state() -> [String: Any] {
            guard let data = try? Data(contentsOf: folder.appendingPathComponent("state.json")),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
            return object
        }
        let invitation = try PairingInvitation.decode(String(contentsOf: folder.appendingPathComponent("invitation.txt"), encoding: .utf8))
        let sender = try AppleTransportIdentity.ephemeral()
        let pairing = try SecurePairingState(localID: "test-sender", localFingerprint: sender.fingerprint,
                                             persisted: nil, persist: { _ in })
        let client = try await Task.detached {
            let client = try SecureReceiverPeer(port: port, identity: sender, state: pairing, invitation: invitation)
            let hello = try client.hello()
            precondition(hello["id"] as? String == invitation.receiverID)
            precondition(hello["device"] as? String == "iPhone")
            return client
        }.value
        defer { client.connection.cancel() }
        try await wait("iOS encrypted connection", seconds: 15) { state()["connected"] as? Bool == true && state()["encrypted"] as? Bool == true }
        let frame = try await Task.detached { try receiverTestH264Frame() }.value
        let config = try JSONSerialization.data(withJSONObject: ["type": "streamConfig", "codec": "h264", "width": 64, "height": 64, "fps": 30])
        client.connection.send(content: ReceiverFrameDecoder.frame(config) + ReceiverFrameDecoder.frame(frame), completion: .contentProcessed { _ in })
        try await wait("iOS synthetic video", seconds: 15) { state()["width"] as? Int == 64 }
        let stranger = NWConnection(host: "127.0.0.1", port: .init(rawValue: port)!, using: .tcp)
        stranger.start(queue: .global())
        defer { stranger.cancel() }
        stranger.send(content: ReceiverFrameDecoder.frame(Data("{\"type\":\"ping\"}".utf8)), completion: .contentProcessed { _ in })
        try await Task.sleep(for: .milliseconds(500))
        precondition(state()["connected"] as? Bool == true && state()["width"] as? Int == 64)
        try Data("revoke".utf8).write(to: folder.appendingPathComponent("command.txt"), options: .atomic)
        try await wait("iOS revocation", seconds: 15) { state()["connected"] as? Bool == false && state()["width"] as? Int == 0 }
        print("iOS receiver: real TLS hello/video, plaintext isolation and live revocation PASS")
    }
}

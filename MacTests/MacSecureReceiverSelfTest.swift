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
        let inputBudget = InputSendBudget(limit: 2)
        let receiver = StreamReceiver(inputBudget: inputBudget, securityProvider: { .tls(identity, state) })
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
            precondition((hello["inputCaps"] as? [String])?.contains(DesktopInputProtocol.capability) == true)
            return client
        }.value
        try await wait { receiver.connected && receiver.encrypted }
        precondition(!receiver.inputForwarding && receiver.inputGrant == nil)
        func grant(_ value: String) throws {
            let data = try JSONSerialization.data(withJSONObject: ["type": "inputConfig", "inputCaps": [DesktopInputProtocol.capability],
                "inputSession": value, "inputStatus": "ready"])
            client.connection.send(content: ReceiverFrameDecoder.frame(data), completion: .contentProcessed { _ in })
        }
        let firstGrant = UUID().uuidString
        try grant(firstGrant)
        try await wait { receiver.inputGrant == firstGrant }
        // Default-off emits no event. Enable, send a key and disable; disable
        // must preserve ordering and deliver releaseAll on the encrypted socket.
        receiver.sendDesktopInput(["kind": "keyDown", "keyCode": 9, "modifiers": 0])
        receiver.setInputForwarding(true)
        receiver.sendDesktopInput(["kind": "keyDown", "keyCode": 0, "modifiers": 8])
        receiver.setInputForwarding(false)
        let input = try await Task.detached { () -> [[String: Any]] in
            var messages: [[String: Any]] = []
            for _ in 0..<10 {
                let object = try client.hello()
                if object["type"] as? String == "desktopInput" { messages.append(object) }
                if messages.count == 2 { return messages }
            }
            throw ReceiverTestFailure(message: "missing desktop input on TLS")
        }.value
        precondition(input[0]["keyCode"] as? Int == 0 && input[0]["inputSession"] as? String == firstGrant)
        precondition(input[1]["kind"] as? String == "releaseAll")
        precondition((input[1]["sequence"] as! Int) > (input[0]["sequence"] as! Int))
        let newGrant = UUID().uuidString
        try grant(newGrant)
        try await wait { receiver.inputGrant == newGrant }
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
        precondition(receiver.inputGrant == nil)
        // A new paired connection starts with no inherited grant or tickets.
        let renewedInvitation = try state.startPairing()
        let renewedClient = try await Task.detached {
            let peer = try SecureReceiverPeer(port: port, identity: sender, state: senderState,
                                              invitation: renewedInvitation)
            _ = try peer.hello()
            return peer
        }.value
        try await wait { receiver.connected && receiver.encrypted }
        precondition(receiver.inputGrant == nil)
        let overflowGrant = UUID().uuidString
        let inputConfig = try JSONSerialization.data(withJSONObject: ["type": "inputConfig", "inputCaps": [DesktopInputProtocol.capability],
            "inputSession": overflowGrant, "inputStatus": "ready"])
        renewedClient.connection.send(content: ReceiverFrameDecoder.frame(inputConfig), completion: .contentProcessed { _ in })
        try await wait { receiver.inputGrant == overflowGrant }
        receiver.setInputForwarding(true)
        guard case .accepted(let oldTicket) = inputBudget.reserve(), case .accepted = inputBudget.reserve() else {
            fatalError("synthetic stalled send admission")
        }
        receiver.sendDesktopInput(["kind": "keyDown", "keyCode": 1, "modifiers": 0])
        try await wait { !receiver.connected && receiver.inputGrant == nil }
        precondition(!inputBudget.complete(oldTicket))
        renewedClient.connection.cancel()
        receiver.stop()
        plain.cancel(); stranger.cancel(); client.connection.cancel()
        try await wait { receiver.listeningPort == 0 }
        print("Mac receiver: TLS hello/video/input, opt-in and release ordering, grant replacement, plaintext isolation and revocation PASS")
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
            precondition((hello["inputCaps"] as? [String])?.contains(PencilProtocol.extendedCapability) == true)
            return client
        }.value
        defer { client.connection.cancel() }
        try await wait("iOS encrypted connection", seconds: 15) { state()["connected"] as? Bool == true && state()["encrypted"] as? Bool == true }
        let frame = try await Task.detached { try receiverTestH264Frame() }.value
        let config = try JSONSerialization.data(withJSONObject: ["type": "streamConfig", "codec": "h264", "width": 64, "height": 64, "fps": 30])
        client.connection.send(content: ReceiverFrameDecoder.frame(config) + ReceiverFrameDecoder.frame(frame), completion: .contentProcessed { _ in })
        try await wait("iOS synthetic video", seconds: 15) { state()["width"] as? Int == 64 }
        let actionGrant = UUID().uuidString
        func pencilConfiguration(extended: Bool) throws {
            var object: [String: Any] = ["type": "inputConfig", "inputCaps": extended
                ? [PencilProtocol.capability, PencilProtocol.extendedCapability] : [PencilProtocol.capability]]
            if extended { object["pencilActionSession"] = actionGrant; object["pencilActionStatus"] = "ready" }
            let data = try JSONSerialization.data(withJSONObject: object)
            client.connection.send(content: ReceiverFrameDecoder.frame(data), completion: .contentProcessed { _ in })
        }
        for extended in [true, false] {
            try pencilConfiguration(extended: extended)
            try await wait("Pencil capabilities", seconds: 15) {
                state()["pencil2"] as? Bool == extended && state()["shortcuts"] as? Bool == extended
            }
            try Data("pencil".utf8).write(to: folder.appendingPathComponent("command.txt"), options: .atomic)
            let controls = try await Task.detached { () -> [[String: Any]] in
                var controls: [[String: Any]] = []
                for _ in 0..<30 {
                    let object = try client.hello()
                    if object["type"] as? String == "touch" { return controls }
                    if ["pencil", "pencil2", "pencilAction"].contains(object["type"] as? String ?? "") { controls.append(object) }
                }
                throw ReceiverTestFailure(message: "Pencil fixture marker missing")
            }.value
            precondition(controls.count == (extended ? 3 : 2))
            precondition(controls[0]["type"] as? String == (extended ? "pencil2" : "pencil"))
            precondition(PencilSample(message: controls[0])?.tool == (extended ? .eraser : .pen))
            precondition(controls[1]["phase"] as? String == "cancel")
            if extended {
                precondition(controls[2]["inputSession"] as? String == actionGrant && controls[2]["action"] as? String == "undo")
            }
        }
        print("iOS Pencil: real TLS V2 rotation/eraser/cancel/shortcut, V1 downgrade and denied shortcut isolation PASS")
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

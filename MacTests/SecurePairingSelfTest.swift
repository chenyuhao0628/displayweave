import Foundation

private enum FixtureFailure: Error { case write }

@main enum SecurePairingSelfTest {
    static func rejects(_ body: () throws -> Void) {
        do { try body(); preconditionFailure("invalid pairing action accepted") } catch { }
    }
    static func main() throws {
        let pin = String(repeating: "01", count: 32), clientPin = String(repeating: "ab", count: 32)
        let fixture = PairingInvitation(receiverID: "receiver", certificateSHA256: pin, token: Data(0..<32))
        let encoded = try fixture.encoded()
        let decoded = try PairingInvitation.decode(encoded)
        precondition(decoded == fixture)
        rejects { _ = try PairingInvitation.decode(encoded + "=") }
        rejects { _ = try PairingInvitation.decode("DW1." + String(repeating: "a", count: 2048)) }
        let auth = SecureAuthRequest(installID: "sender", name: "Test Mac", pairingToken: fixture.token)
        let wire = try auth.encoded()
        let parsed = try SecureAuthRequest.decode(wire)
        precondition(parsed == auth)
        for count in 0..<wire.count { rejects { _ = try SecureAuthRequest.decode(Data(wire.prefix(count))) } }
        rejects { _ = try SecureAuthRequest.decode(wire + Data([0])) }
        rejects { _ = try SecureAuthRequest.decode(Data("{\"type\":\"hello\"}".utf8)) }
        var invalidFlags = wire; invalidFlags[4] = 2
        rejects { _ = try SecureAuthRequest.decode(invalidFlags) }
        rejects { _ = try SecureAuthRequest(installID: "", name: "", pairingToken: nil).encoded() }
        rejects { _ = try SecureAuthRequest(installID: "sender", name: "bad\nname", pairingToken: nil).encoded() }
        let ready = try SecureAuthRequest.ready("receiver")
        let identity = try SecureAuthRequest.readyIdentity(ready)
        precondition(identity == "receiver")
        rejects { _ = try SecureAuthRequest.readyIdentity(ready + Data([0])) }
        let fixtureText = try String(contentsOfFile: "tools/fixtures/secure-pairing-v1.properties", encoding: .utf8)
        let golden = Dictionary(uniqueKeysWithValues: fixtureText.split(separator: "\n").compactMap { line -> (String, String)? in
            guard !line.hasPrefix("#") else { return nil }
            let parts = line.split(separator: "=", maxSplits: 1)
            return parts.count == 2 ? (String(parts[0]), String(parts[1])) : nil
        })
        precondition(golden["invitation"] == encoded)
        precondition(golden["authHex"] == SecurePairingProtocol.hex(wire))
        precondition(golden["readyHex"] == SecurePairingProtocol.hex(ready))

        var clock: Double = 100, stored: Data?, failWrites = false
        let state = try SecurePairingState(localID: "receiver", localFingerprint: pin, persisted: nil,
            now: { clock }, persist: { data in if failWrites { throw FixtureFailure.write }; stored = data })
        precondition(!state.acceptsTLS(clientPin) && !state.hasPairingHistory("sender"))
        let invitation = try state.startPairing()
        precondition(state.acceptsTLS(clientPin))
        let request = SecureAuthRequest(installID: "sender", name: "Test Mac", pairingToken: invitation.token)
        failWrites = true
        rejects { _ = try state.authenticate(request, fingerprint: clientPin) }
        precondition(!state.hasPairingHistory("sender"), "failed persistence granted trust")
        failWrites = false
        let peer = try state.authenticate(request, fingerprint: clientPin)
        precondition(peer.installID == "sender" && state.acceptsTLS(clientPin))
        precondition(!state.pairingOpen && state.hasPairingHistory("sender"))
        precondition(stored != nil)
        let reconnect = try state.authenticate(SecureAuthRequest(installID: "sender", name: "", pairingToken: nil), fingerprint: clientPin)
        precondition(reconnect == peer)
        rejects { _ = try state.authenticate(request, fingerprint: String(repeating: "cd", count: 32)) }
        rejects { _ = try state.authenticate(SecureAuthRequest(installID: "alias", name: "", pairingToken: invitation.token), fingerprint: clientPin) }
        try state.revoke("sender")
        precondition(!state.acceptsTLS(clientPin) && state.hasPairingHistory("sender"), "revocation must retain downgrade tombstone")
        rejects { _ = try state.authenticate(request, fingerprint: clientPin) }
        let repair = try state.startPairing()
        _ = try state.authenticate(SecureAuthRequest(installID: "sender", name: "Test Mac", pairingToken: repair.token), fingerprint: clientPin)
        let restored = try SecurePairingState(localID: "receiver", localFingerprint: pin, persisted: stored,
                                              now: { clock }, persist: { _ in })
        precondition(restored.acceptsTLS(clientPin) && restored.hasPairingHistory("sender"))

        let expired = try state.startPairing()
        clock += 121
        precondition(!state.pairingOpen)
        rejects { _ = try state.authenticate(SecureAuthRequest(installID: "unknown", name: "", pairingToken: expired.token),
                                             fingerprint: String(repeating: "cd", count: 32)) }
        _ = try state.startPairing()
        let wrongToken = SecureAuthRequest(installID: "unknown", name: "", pairingToken: Data(repeating: 0xff, count: 32))
        for _ in 0..<5 { rejects { _ = try state.authenticate(wrongToken, fingerprint: String(repeating: "cd", count: 32)) } }
        precondition(!state.pairingOpen)
        rejects { _ = try SecurePairingState(localID: "receiver", localFingerprint: pin,
                                              persisted: Data("not-json".utf8), persist: { _ in }) }
        rejects { _ = try SecurePairingState(localID: "receiver", localFingerprint: pin,
                                              persisted: Data(repeating: 0, count: 131073), persist: { _ in }) }
        let full = try SecurePairingState(localID: "receiver", localFingerprint: pin, persisted: nil, persist: { _ in })
        for index in 1...128 {
            try full.trustConfirmedReceiver(id: "peer\(index)", name: "Test", fingerprint: String(format: "%064x", index),
                                            explicitInvitation: true)
        }
        rejects { try full.trustConfirmedReceiver(id: "overflow", name: "", fingerprint: clientPin, explicitInvitation: true) }
        precondition(full.peers.count == 128)
        rejects { try full.trustConfirmedReceiver(id: "peer1", name: "", fingerprint: clientPin, explicitInvitation: true) }
        try full.revoke("peer1")
        rejects { try full.trustConfirmedReceiver(id: "peer1", name: "", fingerprint: clientPin, explicitInvitation: false) }
        if CommandLine.arguments.count == 2 {
            let vectors = ["invitation": encoded, "authHex": SecurePairingProtocol.hex(wire),
                           "readyHex": SecurePairingProtocol.hex(ready)]
            try JSONSerialization.data(withJSONObject: vectors, options: [.sortedKeys, .prettyPrinted])
                .write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
        }
        print("Secure pairing: strict framing, full pins, one-use/expired tokens, trust persistence, revocation and downgrade history PASS")
    }
}

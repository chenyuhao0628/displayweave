import Foundation

@main enum SecureTransportPlanSelfTest {
    static func rejects(_ body: () throws -> Void) {
        do { try body(); preconditionFailure("unsafe plan accepted") } catch { }
    }
    static func main() throws {
        let identity = try AppleTransportIdentity.ephemeral(), receiver = try AppleTransportIdentity.ephemeral()
        let state = try SecurePairingState(localID: "sender", localFingerprint: identity.fingerprint,
                                           persisted: nil, persist: { _ in })
        func resolve(_ id: String?, advertised: Bool = false, invitation: PairingInvitation? = nil,
                     legacy: Bool = false) throws -> AppleSenderSecurityPlan {
            try .resolve(identity: identity, pairing: state, receiverID: id, advertisedTLS: advertised,
                         name: "Test", invitation: invitation, allowLegacy: legacy)
        }
        rejects { _ = try resolve("receiver") }
        rejects { _ = try resolve("receiver", advertised: true, legacy: true) }
        let legacy = try resolve(nil, legacy: true)
        precondition(!legacy.encrypted && !legacy.permitsHello(id: nil) && legacy.permitsHello(id: "receiver"))
        let invitation = PairingInvitation(receiverID: "receiver", certificateSHA256: receiver.fingerprint,
                                           token: Data(repeating: 1, count: 32))
        let secure = try resolve(nil, invitation: invitation)
        precondition(secure.encrypted && !secure.permitsHello(id: "receiver"))
        _ = try secure.admission(localName: String(repeating: "名", count: 100))
        try state.trustConfirmedReceiver(id: "receiver", name: "Test", fingerprint: receiver.fingerprint, explicitInvitation: true)
        secure.didAuthenticate()
        precondition(secure.permitsHello(id: "receiver") && !secure.permitsHello(id: "other"))
        precondition(!legacy.permitsHello(id: "receiver"), "legacy learned a previously paired ID")
        let stripped = try resolve("receiver", legacy: true)
        precondition(stripped.encrypted, "stripped Bonjour security field downgraded TLS")
        try state.revoke("receiver")
        precondition(!secure.permitsHello(id: "receiver"))
        rejects { _ = try secure.admission(localName: "Test") }
        rejects { _ = try resolve("receiver", legacy: true) }
        let repair = try resolve("receiver", invitation: invitation)
        precondition(repair.encrypted)
        try state.revokeAllAndInvalidate()
        rejects { _ = try repair.admission(localName: "Test") }
        rejects { _ = try state.startPairing() }
        rejects { try state.revokeAllAndInvalidate() }
        rejects { try state.trustConfirmedReceiver(id: "other", name: "Test", fingerprint: receiver.fingerprint, explicitInvitation: true) }
        precondition(!legacy.permitsHello(id: "neverSeen"), "stale identity allowed legacy after reset")
        print("Security plans: explicit legacy, pin/ID matching, stripped TXT, revocation and reset PASS")
    }
}

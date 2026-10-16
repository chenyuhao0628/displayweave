import Foundation
import Network

private final class AdmissionFixture {
    let queue = DispatchQueue(label: "secure-admission.fixture")
    let identity: AppleTransportIdentity
    let pairing: SecurePairingState
    let pool: AppleSecureAdmissionPool
    let listener: NWListener
    let ready = DispatchSemaphore(value: 0)
    let admitted = DispatchSemaphore(value: 0)
    let rejected = DispatchSemaphore(value: 0)
    var accepted: [NWConnection] = []
    var received: [Data] = []
    var port: UInt16 { listener.port!.rawValue }

    init(timeout: Double = 2) throws {
        identity = try .ephemeral()
        pairing = try SecurePairingState(localID: "receiver", localFingerprint: identity.fingerprint,
                                         persisted: nil, persist: { _ in })
        pool = AppleSecureAdmissionPool(queue: queue, timeout: timeout)
        let state = pairing
        let tls = try AppleTLS.options(identity: identity, peerIsServer: false, queue: queue,
                                        acceptedFingerprint: { state.acceptsTLS($0) })
        listener = try NWListener(using: NWParameters(tls: tls, tcp: NWProtocolTCP.Options()), on: .any)
        listener.newConnectionHandler = { [weak self] connection in
            guard let self else { connection.cancel(); return }
            self.pool.accept(connection, pairing: self.pairing) { result in
                switch result {
                case .success:
                    self.accepted.append(connection)
                    self.admitted.signal()
                    // The first application bytes must survive the admission read.
                    connection.receive(minimumIncompleteLength: 4, maximumLength: 4) { data, _, _, _ in
                        if let data { self.received.append(data) }
                    }
                case .failure: self.rejected.signal()
                }
            }
        }
        listener.stateUpdateHandler = { [weak self] state in
            if case .ready = state { self?.ready.signal() }
        }
        listener.start(queue: queue)
        precondition(ready.wait(timeout: .now() + 3) == .success)
    }
    func stop() { queue.sync { pool.cancelAll(); listener.cancel(); accepted.forEach { $0.cancel() } } }
}

@main enum SecureAdmissionSelfTest {
    private static func client(_ fixture: AdmissionFixture, identity: AppleTransportIdentity,
                       state: SecurePairingState, token: Data?, id: String = "receiver",
                       timeout: Double = 2) throws -> (Bool, NWConnection) {
        let done = DispatchSemaphore(value: 0)
        var succeeded = false
        let tls = try AppleTLS.options(identity: identity, peerIsServer: true, queue: fixture.queue,
                                        acceptedFingerprint: { $0 == fixture.identity.fingerprint })
        let connection = NWConnection(host: "127.0.0.1", port: .init(rawValue: fixture.port)!,
                                      using: NWParameters(tls: tls, tcp: .init()))
        let plan = SecureClientAdmission(pairing: state, receiverID: id, receiverName: "Test Receiver",
                                         fingerprint: fixture.identity.fingerprint, token: token, localName: "Test Sender")
        let admission = AppleSecureAdmission(connection: connection, queue: fixture.queue, timeout: timeout) { result in
            if case .success = result { succeeded = true }
            done.signal()
        }
        fixture.queue.async { admission.startClient(plan) }
        precondition(done.wait(timeout: .now() + 4) == .success, "admission did not terminate")
        withExtendedLifetime(admission) {}
        return (succeeded, connection)
    }

    static func main() throws {
        let server = try AdmissionFixture()
        defer { server.stop() }
        let sender = try AppleTransportIdentity.ephemeral()
        let state = try SecurePairingState(localID: "sender", localFingerprint: sender.fingerprint,
                                           persisted: nil, persist: { _ in })
        let invitation = try server.pairing.startPairing()
        let (paired, connection) = try client(server, identity: sender, state: state, token: invitation.token)
        precondition(paired && state.trustedPeer("receiver") != nil)
        precondition(server.admitted.wait(timeout: .now() + 2) == .success)
        connection.send(content: Data("NEXT".utf8), completion: .contentProcessed { _ in })
        let deadline = Date().addingTimeInterval(2)
        while server.queue.sync(execute: { server.received.isEmpty }) && Date() < deadline { Thread.sleep(forTimeInterval: 0.01) }
        precondition(server.queue.sync { server.received == [Data("NEXT".utf8)] })

        let (reconnected, second) = try client(server, identity: sender, state: state, token: nil)
        precondition(reconnected)
        precondition(server.admitted.wait(timeout: .now() + 2) == .success)
        defer { connection.cancel(); second.cancel() }

        let stranger = try AppleTransportIdentity.ephemeral()
        let strangerState = try SecurePairingState(localID: "stranger", localFingerprint: stranger.fingerprint,
                                                  persisted: nil, persist: { _ in })
        _ = try server.pairing.startPairing()
        let (badToken, bad) = try client(server, identity: stranger, state: strangerState, token: Data(repeating: 0, count: 32))
        defer { bad.cancel() }
        precondition(!badToken && strangerState.peers.isEmpty)
        precondition(server.queue.sync { server.accepted.count == 2 }, "untrusted socket reached application")

        // Even a correctly pinned TLS server must acknowledge the selected ID.
        let (wrongID, mismatched) = try client(server, identity: sender, state: state, token: nil, id: "other")
        mismatched.cancel()
        precondition(!wrongID && state.trustedPeer("other") == nil)

        try server.pairing.revoke("sender")
        server.pairing.stopPairing()
        let (revoked, rejected) = try client(server, identity: sender, state: state, token: nil)
        rejected.cancel()
        precondition(!revoked)

        // Real TLS with malformed/oversized/pre-application payloads must never
        // invoke the receiver. Header and payload arrive in separate writes.
        let malformed = try AdmissionFixture()
        defer { malformed.stop() }
        _ = try malformed.pairing.startPairing()
        for payload in [Data([0, 0, 16, 1]), Data([0, 0, 0, 4]) + Data("HELO".utf8)] {
            let done = DispatchSemaphore(value: 0)
            let tls = try AppleTLS.options(identity: stranger, peerIsServer: true, queue: malformed.queue,
                                            acceptedFingerprint: { $0 == malformed.identity.fingerprint })
            let raw = NWConnection(host: "127.0.0.1", port: .init(rawValue: malformed.port)!,
                                   using: NWParameters(tls: tls, tcp: .init()))
            raw.stateUpdateHandler = { event in
                if case .ready = event {
                    raw.send(content: payload.prefix(2), completion: .contentProcessed { _ in
                        raw.send(content: payload.dropFirst(2), completion: .contentProcessed { _ in done.signal() })
                    })
                }
            }
            raw.start(queue: malformed.queue)
            precondition(done.wait(timeout: .now() + 3) == .success)
            precondition(malformed.rejected.wait(timeout: .now() + 3) == .success)
            raw.cancel()
        }
        precondition(malformed.queue.sync { malformed.accepted.isEmpty })

        // A stalled plaintext TCP peer occupies only the bounded admission pool.
        let slow = try AdmissionFixture(timeout: 0.5)
        defer { slow.stop() }
        let plain = (0..<3).map { _ in NWConnection(host: "127.0.0.1", port: .init(rawValue: slow.port)!, using: .tcp) }
        plain.forEach { $0.start(queue: slow.queue) }
        defer { plain.forEach { $0.cancel() } }
        precondition(slow.rejected.wait(timeout: .now() + 2) == .success)
        Thread.sleep(forTimeInterval: 0.7)
        precondition(slow.queue.sync { slow.pool.pendingCount == 0 && slow.accepted.isEmpty })
        print("Secure admission pairing, reconnect, exact reads, rejection and bounded timeout PASS")
    }
}

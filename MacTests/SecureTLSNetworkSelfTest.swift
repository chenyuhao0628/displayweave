import Foundation
import Network

private final class TLSEchoFixture: @unchecked Sendable {
    let queue = DispatchQueue(label: "displayweave.tls.test")
    let listener: NWListener
    let ready = DispatchSemaphore(value: 0)
    let received = DispatchSemaphore(value: 0)
    private var connections: [NWConnection] = []
    init(identity: AppleTransportIdentity, clientPin: String) throws {
        let tls = try AppleTLS.options(identity: identity, peerIsServer: false, queue: queue) { $0 == clientPin }
        let params = NWParameters(tls: tls, tcp: NWProtocolTCP.Options())
        params.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        listener = try NWListener(using: params)
        listener.stateUpdateHandler = { [weak self] state in
            if case .ready = state { self?.ready.signal() }
        }
        listener.newConnectionHandler = { [weak self] connection in
            guard let self, self.connections.count < 8 else { connection.cancel(); return }
            self.connections.append(connection)
            connection.stateUpdateHandler = { [weak self] state in
                guard let self else { return }
                if case .ready = state {
                    precondition(AppleTLS.peerFingerprint(connection) == clientPin)
                    connection.receive(minimumIncompleteLength: 5, maximumLength: 5) { data, _, _, error in
                        if error == nil, data == Data("probe".utf8) {
                            connection.send(content: data, completion: .contentProcessed { _ in self.received.signal() })
                        }
                    }
                }
            }
            connection.start(queue: self.queue)
        }
        listener.start(queue: queue)
        guard ready.wait(timeout: .now() + 5) == .success else { throw TransportSecurityError.failed("TLS test listener timeout") }
    }
    var port: UInt16 { listener.port!.rawValue }
    func stop() {
        queue.sync {
            listener.cancel()
            for connection in connections { connection.stateUpdateHandler = nil; connection.cancel() }
            connections.removeAll()
        }
    }
}

@main enum SecureTLSNetworkSelfTest {
    private static func probe(port: UInt16, identity: AppleTransportIdentity, serverPin: String) throws -> Bool {
        let queue = DispatchQueue(label: "displayweave.tls.probe")
        let done = DispatchSemaphore(value: 0)
        var accepted = false
        let options = try AppleTLS.options(identity: identity, peerIsServer: true, queue: queue) { $0 == serverPin }
        let conn = NWConnection(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: port)!,
                                using: NWParameters(tls: options, tcp: NWProtocolTCP.Options()))
        conn.stateUpdateHandler = { state in
            switch state {
            case .ready:
                precondition(AppleTLS.peerFingerprint(conn) == serverPin)
                conn.send(content: Data("probe".utf8), completion: .contentProcessed { _ in })
                conn.receive(minimumIncompleteLength: 5, maximumLength: 5) { data, _, _, error in
                    accepted = error == nil && data == Data("probe".utf8)
                    done.signal()
                }
            case .failed, .waiting: done.signal()
            default: break
            }
        }
        conn.start(queue: queue)
        let finished = done.wait(timeout: .now() + 5)
        queue.sync { conn.stateUpdateHandler = nil; conn.cancel() }
        precondition(finished == .success, "TLS handshake/read did not terminate")
        return accepted
    }

    static func main() throws {
        let serverIdentity = try AppleTransportIdentity.ephemeral()
        if CommandLine.arguments.count == 5 && CommandLine.arguments[1] == "--java-server" {
            let serverCert = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[2]))
            try serverIdentity.certificateDER.write(to: URL(fileURLWithPath: CommandLine.arguments[3]), options: .atomic)
            let deadline = Date().addingTimeInterval(10)
            while !FileManager.default.fileExists(atPath: CommandLine.arguments[4]) && Date() < deadline {
                Thread.sleep(forTimeInterval: 0.05)
            }
            let port = UInt16(try String(contentsOfFile: CommandLine.arguments[4], encoding: .utf8))!
            let accepted = try probe(port: port, identity: serverIdentity,
                                     serverPin: AppleTransportIdentity.fingerprint(serverCert))
            precondition(accepted, "Apple → Java TLS failed")
            print("Apple → Java mutual TLS and pinned certificate PASS")
            return
        }
        if CommandLine.arguments.count == 4 && CommandLine.arguments[1] == "--java-peer" {
            let clientCert = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[2]))
            let server = try TLSEchoFixture(identity: serverIdentity,
                                            clientPin: AppleTransportIdentity.fingerprint(clientCert))
            defer { server.stop() }
            let ready = "\(server.port)\n\(serverIdentity.fingerprint)\n"
            try ready.write(toFile: CommandLine.arguments[3], atomically: true, encoding: .utf8)
            precondition(server.received.wait(timeout: .now() + 20) == .success, "Java TLS probe missing")
            print("Java → Apple mutual TLS and pinned certificate PASS")
            return
        }
        let client = try AppleTransportIdentity.ephemeral()
        let stranger = try AppleTransportIdentity.ephemeral()
        let server = try TLSEchoFixture(identity: serverIdentity, clientPin: client.fingerprint)
        defer { server.stop() }
        let initial = try probe(port: server.port, identity: client, serverPin: serverIdentity.fingerprint)
        let reconnect = try probe(port: server.port, identity: client, serverPin: serverIdentity.fingerprint)
        let wrongServer = try probe(port: server.port, identity: client, serverPin: stranger.fingerprint)
        let wrongClient = try probe(port: server.port, identity: stranger, serverPin: serverIdentity.fingerprint)
        precondition(initial && reconnect && !wrongServer && !wrongClient)
        print("Apple mutual TLS loopback, fresh reconnect, wrong server/client pin rejection PASS")
    }
}

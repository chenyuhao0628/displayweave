import Foundation
import Network

@main enum UsbmuxTLSRelaySelfTest {
    nonisolated static func echo(_ connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { data, _, ended, error in
            guard error == nil, let data, !data.isEmpty else { return }
            connection.send(content: data, completion: .contentProcessed { error in
                if error == nil && !ended { echo(connection) }
            })
        }
    }
    static func main() throws {
        let queue = DispatchQueue(label: "relay.test")
        let ready = DispatchSemaphore(value: 0), closed = DispatchSemaphore(value: 0)
        let listener = try NWListener(using: .tcp, on: .any)
        var upstream: NWConnection?
        listener.newConnectionHandler = { connection in
            upstream = connection
            connection.start(queue: queue)
            echo(connection)
        }
        listener.stateUpdateHandler = { if case .ready = $0 { ready.signal() } }
        listener.start(queue: queue)
        precondition(ready.wait(timeout: .now() + 3) == .success)
        let tunnel = NWConnection(host: "127.0.0.1", port: listener.port!, using: .tcp)
        tunnel.stateUpdateHandler = { if case .ready = $0 { ready.signal() } }
        tunnel.start(queue: queue)
        precondition(ready.wait(timeout: .now() + 3) == .success)
        let relay = UsbmuxTLSRelay(tunnel: tunnel, queue: queue)
        var relayPort: UInt16 = 0
        queue.async {
            relay.onClosed = { closed.signal() }
            relay.start { if case .success(let port) = $0 { relayPort = port }; ready.signal() }
        }
        precondition(ready.wait(timeout: .now() + 3) == .success && relayPort != 0)
        let client = NWConnection(host: "127.0.0.1", port: .init(rawValue: relayPort)!, using: .tcp)
        let bytes = Data((0..<200_000).map { UInt8($0 % 251) })
        var response = Data()
        client.stateUpdateHandler = { state in
            if case .ready = state {
                client.send(content: bytes, completion: .contentProcessed { _ in })
                client.receive(minimumIncompleteLength: bytes.count, maximumLength: bytes.count) { data, _, _, error in
                    if error == nil, let data { response = data }; ready.signal()
                }
            }
        }
        client.start(queue: queue)
        precondition(ready.wait(timeout: .now() + 5) == .success && response == bytes)
        queue.sync { relay.stop(); relay.stop() }
        precondition(closed.wait(timeout: .now() + 2) == .success)
        precondition(closed.wait(timeout: .now() + 0.1) == .timedOut, "duplicate close callback")
        queue.sync { client.cancel(); upstream?.cancel(); listener.cancel() }
        print("USB TLS loopback relay bounded full-duplex chunks and owned teardown PASS")
    }
}

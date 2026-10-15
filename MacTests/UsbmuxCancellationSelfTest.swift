import Foundation
import Network

private final class AcceptedConnection: @unchecked Sendable { var connection: NWConnection? }

@main struct UsbmuxCancellationSelfTest {
    @MainActor static func main() async throws {
        // Exercise the real usbmux framing read against a silent loopback peer;
        // cancellation must release a suspended read without waiting for bytes.
        let deadline = Task.detached {
            try await Task.sleep(for: .seconds(5))
            fatalError("cancelled usbmux operation did not finish")
        }
        defer { deadline.cancel() }
        let listener = try NWListener(using: .tcp, on: .any)
        let accepted = AcceptedConnection()
        listener.newConnectionHandler = { conn in accepted.connection = conn; conn.start(queue: .main) }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            listener.stateUpdateHandler = { state in
                if case .ready = state { continuation.resume() }
                if case .failed(let error) = state { continuation.resume(throwing: error) }
            }
            listener.start(queue: .main)
        }
        defer { listener.cancel(); accepted.connection?.cancel() }
        let client = NWConnection(host: "127.0.0.1", port: listener.port!, using: .tcp)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            client.stateUpdateHandler = { state in
                if case .ready = state { continuation.resume() }
                if case .failed(let error) = state { continuation.resume(throwing: error) }
            }
            client.start(queue: .main)
        }
        client.stateUpdateHandler = nil
        let read = Task { try await Usbmux.readMessage(on: client) }
        try await Task.sleep(for: .milliseconds(100))
        read.cancel()
        do { _ = try await read.value; fatalError("cancelled read returned data") }
        catch { }
        let opening = Task { try await Usbmux.open(queue: .main) }
        opening.cancel()
        do { let conn = try await opening.value; conn.cancel(); fatalError("cancelled open succeeded") }
        catch is CancellationError { }
        print("Usbmux cancellation releases silent read and cancelled open PASS")
    }
}

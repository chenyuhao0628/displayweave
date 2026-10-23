import Foundation
import Network

private final class WireCapture: @unchecked Sendable {
    private let lock = NSLock()
    private var videos: [Int] = []
    private var cursors = 0
    private var failure: String?
    private var decoder = ReceiverFrameDecoder() // receive queue only
    private var connection: NWConnection?

    func accept(_ conn: NWConnection, on queue: DispatchQueue) {
        lock.withLock { connection = conn }
        conn.start(queue: queue)
        receive(conn)
    }

    private func receive(_ conn: NWConnection) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { data, _, ended, error in
            if let data {
                do {
                    for frame in try self.decoder.append(data) {
                        if frame.first == UInt8(ascii: "{") {
                            let obj = try JSONSerialization.jsonObject(with: frame) as! [String: Any]
                            precondition(obj["type"] as? String == "cursor" && obj["s"] != nil)
                            self.lock.withLock { self.cursors += 1 }
                        } else {
                            precondition(frame.count == 256 * 1024)
                            let index = frame.prefix(4).withUnsafeBytes {
                                Int(UInt32(bigEndian: $0.loadUnaligned(as: UInt32.self)))
                            }
                            precondition(frame.dropFirst(4).allSatisfy { $0 == 0xa5 }, "interleaved cursor/video bytes")
                            self.lock.withLock { self.videos.append(index) }
                        }
                    }
                } catch { self.lock.withLock { self.failure = String(describing: error) } }
            }
            if !ended && error == nil { self.receive(conn) }
        }
    }

    var snapshot: (videos: [Int], cursors: Int, failure: String?) {
        lock.withLock { (videos, cursors, failure) }
    }
    func stop() { lock.withLock { connection?.cancel() } }
}

@main enum CursorWireSelfTest {
    static func main() throws {
        let receiveQueue = DispatchQueue(label: "test.cursor.receive")
        let callbackQueue = DispatchQueue(label: "test.cursor.video")
        let capture = WireCapture()
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        let listener = try NWListener(using: parameters)
        let listening = DispatchSemaphore(value: 0)
        listener.stateUpdateHandler = { if case .ready = $0 { listening.signal() } }
        listener.newConnectionHandler = { capture.accept($0, on: receiveQueue) }
        listener.start(queue: receiveQueue)
        defer { listener.cancel(); capture.stop() }
        precondition(listening.wait(timeout: .now() + 3) == .success)
        let connection = NWConnection(host: "127.0.0.1", port: listener.port!, using: .tcp)
        defer { connection.cancel() }
        let ready = DispatchSemaphore(value: 0)
        connection.stateUpdateHandler = { if case .ready = $0 { ready.signal() } }
        connection.start(queue: callbackQueue)
        precondition(ready.wait(timeout: .now() + 3) == .success)
        let echo = CursorEcho()
        var sample = 0 // echo sampling queue only
        echo.start(sample: {
            sample += 1
            return CursorPosition(x: Double(sample % 100) / 100, y: 0.5, visible: true)
        }, write: CursorEcho.writer(on: connection))
        defer { echo.stop() }
        let slots = DispatchSemaphore(value: 3)
        let sent = DispatchGroup()
        for index in 0..<48 {
            precondition(slots.wait(timeout: .now() + 3) == .success)
            if index % 12 == 0 {
                // Model a synchronous encoder occupying the callback queue.
                callbackQueue.async { Thread.sleep(forTimeInterval: 0.04) }
            }
            var payload = Data(repeating: 0xa5, count: 256 * 1024)
            var value = UInt32(index).bigEndian
            withUnsafeBytes(of: &value) { payload.replaceSubrange(0..<4, with: $0) }
            sent.enter()
            connection.send(content: ReceiverFrameDecoder.frame(payload), completion: .contentProcessed { error in
                precondition(error == nil); slots.signal(); sent.leave()
            })
            Thread.sleep(forTimeInterval: 0.002)
        }
        precondition(sent.wait(timeout: .now() + 3) == .success)
        for _ in 0..<300 {
            let snapshot = capture.snapshot
            if snapshot.videos.count == 48 && snapshot.cursors > 0 { break }
            Thread.sleep(forTimeInterval: 0.01)
        }
        echo.stop()
        let result = capture.snapshot
        precondition(result.failure == nil && result.videos == Array(0..<48) && result.cursors > 0)
        print("CursorWireSelfTest PASS: 48 × 256 KiB ordered video payloads + \(result.cursors) cursor messages, no framing corruption")
    }
}

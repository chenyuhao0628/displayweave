import Foundation

private final class Writes: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [(Double, (Bool) -> Void)] = []
    let arrived = DispatchSemaphore(value: 0)
    func accept(_ data: Data, _ complete: @escaping (Bool) -> Void) {
        var decoder = ReceiverFrameDecoder()
        let frames = try! decoder.append(data)
        precondition(frames.count == 1)
        let object = try! JSONSerialization.jsonObject(with: frames[0]) as! [String: Any]
        precondition(object["type"] as? String == "cursor")
        lock.withLock { values.append((object["x"] as! Double, complete)) }
        arrived.signal()
    }
    var count: Int { lock.withLock { values.count } }
    func at(_ index: Int) -> (Double, (Bool) -> Void) { lock.withLock { values[index] } }
}

@main enum CursorLatencySelfTest {
    static func main() {
        let relay = LatestValueRelay<Int>()
        let first = relay.offer(0)!
        for value in 1...10_000 { precondition(relay.offer(value) == nil) }
        precondition(relay.take(first) == 10_000, "slow consumer must take newest position")
        precondition(relay.offer(10_001) == nil, "one delivery may be in flight")
        let second = relay.complete(first)!
        precondition(relay.take(second) == 10_001)
        let oldEpoch = relay.generation
        relay.reset()
        precondition(relay.generation != oldEpoch)
        let replacement = relay.offer(20_000)!
        precondition(relay.take(second) == nil && relay.complete(second) == nil,
                     "retired callback must not drain replacement session")
        precondition(relay.take(replacement) == 20_000)
        precondition(relay.complete(replacement) == nil)

        let echo = CursorEcho()
        let writes = Writes()
        let sampled = DispatchSemaphore(value: 0)
        var sample = 0 // owned exclusively by the echo's sampling queue
        echo.start(sample: {
            sample += 1
            if sample == 12 { sampled.signal() }
            return CursorPosition(x: Double(sample) / 10_000, y: 0.5, visible: true)
        }, write: { data, complete in writes.accept(data, complete) })
        precondition(writes.arrived.wait(timeout: .now() + 2) == .success)
        // A transport/completion stall must not stop sampling or submit a growing
        // list of writes. This also isolates sampling from a busy caller thread.
        precondition(sampled.wait(timeout: .now() + 2) == .success,
                     "sampling stalled behind the blocked consumer")
        precondition(writes.count == 1, "cursor writes accumulated under backpressure")
        writes.at(0).1(true)
        precondition(writes.arrived.wait(timeout: .now() + 2) == .success)
        precondition(writes.at(1).0 > writes.at(0).0 + 0.0004,
                     "completion replayed stale position instead of latest sample")
        echo.stop()
        let newer = Writes()
        echo.start(sample: { CursorPosition(x: 0.75, y: 0.5, visible: true) },
                   write: { data, complete in newer.accept(data, complete) })
        precondition(newer.arrived.wait(timeout: .now() + 2) == .success)
        writes.at(1).1(true) // delayed completion from the previous session
        Thread.sleep(forTimeInterval: 0.04)
        precondition(newer.count == 1 && newer.at(0).0 == 0.75)
        newer.at(0).1(false)
        echo.stop()
        print("CursorLatencySelfTest PASS: 10001 updates coalesced, bounded writes, independent sampling, stale completions")
    }
}

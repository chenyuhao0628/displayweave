import Foundation

@main enum ReceiverVideoFlowSelfTest {
    static func main() {
        var pressure = ReceiverVideoBackpressurePolicy()
        precondition(pressure.action(isReady: false, now: 1) == .enqueue)
        precondition(pressure.action(isReady: true, now: 1.016) == .enqueue)
        for i in 0..<30 {
            precondition(pressure.action(isReady: true, now: 2 + Double(i) / 60) == .enqueue)
        }
        precondition(pressure.action(isReady: false, now: 3) == .enqueue)
        precondition(pressure.action(isReady: false, now: 3.016) == .enqueue)
        precondition(pressure.action(isReady: false, now: 3.032) == .flushAndWait)
        for _ in 0..<200 { precondition(pressure.action(isReady: false, now: 4) == .wait) }
        precondition(pressure.action(isReady: true, now: 5) == .enqueue)
        precondition(pressure.action(isReady: false, now: 6) == .enqueue)
        precondition(pressure.action(isReady: false, now: 6.051) == .flushAndWait)

        var first = ReceiverFirstVideoDeadline()
        precondition(!first.expired(at: 100))
        first.begin(at: 10)
        precondition(!first.expired(at: 24.9) && first.expired(at: 25))
        first.receivedFrame()
        precondition(!first.expired(at: 100_000), "a static desktop after first video must stay connected")
        first.begin(at: 100_000)
        precondition(first.expired(at: 100_015), "replacement receives its own deadline")
        print("Shared Apple video flow: transient pressure, bounded flush, first-frame and idle semantics PASS")
    }
}

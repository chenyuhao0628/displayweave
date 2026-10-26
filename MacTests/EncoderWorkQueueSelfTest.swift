import Foundation

@main enum EncoderWorkQueueSelfTest {
    static func main() {
        let encoder = EncoderWorkQueue()
        let state = DispatchQueue(label: "test.state")
        let entered = DispatchSemaphore(value: 0)
        let release = DispatchSemaphore(value: 0)
        let control = DispatchSemaphore(value: 0)
        let output = DispatchSemaphore(value: 0)
        let retired = DispatchSemaphore(value: 0)
        state.async {
            precondition(encoder.submit(limit: 2) {
                entered.signal()
                precondition(release.wait(timeout: .now() + 3) == .success)
                state.async { output.signal() }
            })
            precondition(encoder.submit(limit: 2) {})
            precondition(!encoder.submit(limit: 2) { fatalError("unbounded admission") })
        }
        precondition(entered.wait(timeout: .now() + 3) == .success)
        // This would time out when EncodeFrame ran on sender.video itself.
        state.async { control.signal() }
        precondition(control.wait(timeout: .now() + 1) == .success,
                     "a blocking encode must not delay input/network/capture callbacks")
        state.async {
            encoder.perform { _ = retired.signal() }
        }
        precondition(retired.wait(timeout: .now() + 0.05) == .timedOut,
                     "retirement must not overlap an active submission")
        release.signal()
        precondition(retired.wait(timeout: .now() + 3) == .success)
        precondition(output.wait(timeout: .now() + 3) == .success,
                     "retirement must not deadlock the callback owner")
        precondition(encoder.submit(limit: 1) {})
        encoder.perform {}
        print("Encoder submission isolation, bounded admission and serialized retirement PASS")
    }
}

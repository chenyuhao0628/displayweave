import Foundation

@MainActor private final class Gate {
    var continuation: CheckedContinuation<Void, Never>?
    func wait() async { await withCheckedContinuation { continuation = $0 } }
    func open() { continuation?.resume(); continuation = nil }
}
private enum StartFailure: Error { case refused }

@main struct SessionLifetimeSelfTest {
    @MainActor static func spin(until ready: () -> Bool) async {
        for _ in 0..<200 { if ready() { return }; await Task.yield() }
        precondition(ready(), "timed out")
    }
    @MainActor static func main() async {
        var stops = 0, errors = 0
        let failed = SessionLifetime(start: { throw StartFailure.refused }, stop: {
            stops += 1; return Task {}
        }) { _ in errors += 1 }
        failed.start()
        await spin { errors == 1 }
        precondition(stops == 1, "failed startup leaked its pipeline")
        await failed.stop().value
        await failed.stop().value
        precondition(stops == 1, "cleanup must run once")

        let startGate = Gate(), stopGate = Gate()
        var entered = false, finished = false, cleaned = false
        let active = SessionLifetime(start: { entered = true; await startGate.wait() }, stop: {
            Task { await stopGate.wait(); cleaned = true }
        }) { _ in preconditionFailure("cancelled start reported failure") }
        active.start()
        await spin { entered }
        let cleanup = active.stop()
        Task { await cleanup.value; finished = true }
        await spin { stopGate.continuation != nil }
        stopGate.open()
        await spin { cleaned }
        precondition(!finished, "cleanup finished before in-flight start returned")
        startGate.open()
        await cleanup.value
        await spin { finished }
        active.start() // cannot resurrect the stopped pipeline
        precondition(cleaned)
        print("Session lifetime: startup failure cleanup, idempotent stop and suspended-start barrier PASS")
    }
}

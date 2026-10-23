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
        let failureGate = Gate()
        var runtimeStarted = false, runtimeStops = 0, runtimeErrors = 0
        let runtime = SessionLifetime(start: { runtimeStarted = true }, stop: {
            runtimeStops += 1
            return Task { await failureGate.wait() }
        }) { _ in runtimeErrors += 1 }
        runtime.start()
        await spin { runtimeStarted }
        let failure = runtime.fail(StartFailure.refused)
        _ = runtime.fail(StartFailure.refused)
        await spin { failureGate.continuation != nil }
        precondition(runtimeErrors == 0 && runtimeStops == 1, "failure must wait for owned cleanup")
        failureGate.open()
        await failure.value
        precondition(runtimeErrors == 1, "a runtime failure must be reported once")
        await runtime.stop().value
        await runtime.fail(StartFailure.refused).value
        precondition(runtimeStops == 1 && runtimeErrors == 1, "a stopped session cannot be failed again")

        let retiringGate = Gate()
        var retiringStops = 0, staleErrors = 0
        let retiring = SessionLifetime(start: {}, stop: {
            retiringStops += 1
            return Task { await retiringGate.wait() }
        }) { _ in staleErrors += 1 }
        retiring.start()
        let retiringFailure = retiring.fail(StartFailure.refused)
        await spin { retiringGate.continuation != nil }
        let retired = retiring.stop()
        retiringGate.open()
        await retired.value
        await retiringFailure.value
        precondition(retiringStops == 1 && staleErrors == 0, "replacement must suppress a retiring session's late failure")
        print("Session lifetime: startup/runtime failure cleanup, idempotence, cancellation and suspended-start barrier PASS")
    }
}

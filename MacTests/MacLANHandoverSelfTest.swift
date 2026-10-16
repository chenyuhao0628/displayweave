import Foundation

@main enum MacLANHandoverSelfTest {
    @MainActor static func main() async {
        let wired = MacLANRoute(interfaceName: "bridge0", direct: true)
        let wifi = MacLANRoute(interfaceName: "en0", direct: false, wireless: true)
        var policy = MacLANHandoverPolicy()
        precondition(!policy.upgrade(peer: "A", current: wifi, candidate: wired, now: 0, enabled: false))
        precondition(!policy.upgrade(peer: "A", current: wifi, candidate: wired, now: 1, enabled: true))
        precondition(!policy.upgrade(peer: "A", current: wifi, candidate: nil, now: 2, enabled: true))
        precondition(!policy.upgrade(peer: "A", current: wifi, candidate: wired, now: 3, enabled: true))
        precondition(policy.upgrade(peer: "A", current: wifi, candidate: wired, now: 5, enabled: true))
        precondition(!policy.upgrade(peer: "A", current: wired, candidate: wired, now: 8, enabled: true))
        precondition(!policy.upgrade(peer: "A", current: wifi, candidate: wired, now: 10, enabled: true))
        precondition(policy.recover(peer: "A", now: 11, enabled: true))
        precondition(policy.recover(peer: "A", now: 12, enabled: true))
        precondition(!policy.recover(peer: "A", now: 13, enabled: true), "flapping must stop")
        precondition(policy.isSuppressed("A"))
        precondition(!policy.recover(peer: "A", now: 1000, enabled: true), "exhaustion needs explicit retry")
        policy.manualConnect("A")
        precondition(policy.recover(peer: "A", now: 1001, enabled: true))
        policy.disconnect("A")
        precondition(!policy.recover(peer: "A", now: 1002, enabled: true))
        policy.manualConnect("A")
        precondition(!policy.recover(peer: "A", now: 1003, enabled: false))
        precondition(!policy.recover(peer: "", now: 1003, enabled: true))
        precondition(!policy.recover(peer: String(repeating: "x", count: 257), now: 1003, enabled: true))
        precondition(!policy.recover(peer: "A", now: .nan, enabled: true))

        let peers = [MacLANCandidateIdentity(installID: "B", route: wired),
                     MacLANCandidateIdentity(installID: "A", route: wifi)]
        precondition(MacLANHandoverPolicy.select(peer: "A", candidates: peers, failed: []) == wifi)
        precondition(MacLANHandoverPolicy.select(peer: "A", candidates: peers, failed: [wifi]) == nil)
        precondition(MacLANHandoverPolicy.select(peer: "missing", candidates: peers, failed: []) == nil)
        let both = peers + [MacLANCandidateIdentity(installID: "A", route: wired)]
        precondition(MacLANHandoverPolicy.select(peer: "A", candidates: both, failed: []) == wired)
        precondition(MacLANHandoverPolicy.select(peer: "A", candidates: both, failed: [wired]) == wifi)
        let relabeledCable = MacLANCandidateIdentity(installID: "A",
            route: MacLANRoute(interfaceName: "bridge0", direct: false))
        precondition(MacLANHandoverPolicy.select(peer: "A", candidates: both + [relabeledCable],
                                                failed: [wired]) == wifi)
        for n in 0..<300 { policy.disconnect("peer\(n)") }
        precondition(policy.trackedCount <= 256)
        precondition(!policy.recover(peer: "untracked", now: 2000, enabled: true), "capacity must fail closed")
        precondition(MacLANHandoverPolicy.recoveryDelays == [0.5, 1, 2, 4, 8])
        await testRecoveryRunner()
        print("Mac LAN handover: same ID, candidate stability, cooldown, flapping, bounded recovery and opt-out PASS")
    }

    @MainActor static func testRecoveryRunner() async {
        var stopped = false, starts = 0, delays: [Double] = []
        let cleanup = Task { @MainActor in
            await Task.yield()
            stopped = true
        }
        let success = await MacLANRecoveryRunner.run(cleanup: cleanup, current: { true },
            pause: { delays.append($0) }, attempt: { index in
                precondition(stopped, "replacement began before resources stopped")
                starts += 1
                return index == 1
            })
        precondition(success == .connected && starts == 2 && delays == [0.5, 1])
        var currentGeneration = 1
        starts = 0
        let stale = await MacLANRecoveryRunner.run(cleanup: Task {}, current: { currentGeneration == 1 },
            pause: { _ in currentGeneration = 2 }, attempt: { _ in starts += 1; return true })
        precondition(stale == .cancelled && starts == 0, "stale role/peer task opened a connection")
        let exhausted = await MacLANRecoveryRunner.run(cleanup: Task {}, current: { true },
            pause: { _ in }, attempt: { _ in starts += 1; return false })
        precondition(exhausted == .exhausted && starts == 5, "retry budget is finite")
        starts = 0
        let cancelled = await MacLANRecoveryRunner.run(cleanup: Task {}, current: { true },
            pause: { _ in throw CancellationError() }, attempt: { _ in starts += 1; return true })
        precondition(cancelled == .cancelled && starts == 0)
    }
}

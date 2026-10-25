import CoreGraphics
import Foundation

@MainActor private final class DisplayPeer: DisplayUnitParticipant {
    var identity: DisplayUnitIdentity?
    var events: [String] = []
    var stopped = false
    var rebuilding: (() async -> Void)?
    init(_ id: UInt32, _ unit: UInt32) { identity = DisplayUnitIdentity(displayID: id, unit: unit) }
    var displayUnitIdentity: DisplayUnitIdentity? { stopped ? nil : identity }
    func releaseDisplayForRenumbering(expectedID: UInt32) async -> Bool {
        guard !stopped, identity?.displayID == expectedID else { return false }
        events.append("release"); identity = nil; return true
    }
    func resumeAfterDisplayRenumbering() async {
        if !stopped { events.append("rebuild"); await rebuilding?() }
    }
}

@MainActor private final class DisplayGate {
    var continuation: CheckedContinuation<Void, Never>?
    func wait() async { await withCheckedContinuation { continuation = $0 } }
    func open() { continuation?.resume(); continuation = nil }
}

@main struct DisplayRecoverySelfTest {
    @MainActor static func spin(_ ready: () -> Bool) async {
        for _ in 0..<500 { if ready() { return }; await Task.yield() }
        precondition(ready())
    }

    @MainActor static func main() async throws {
        let saved = CGPoint(x: -424, y: -1152), system = CGPoint(x: 1512, y: 0)
        let t = Date(timeIntervalSinceReferenceDate: 0)
        var restore = OriginRestore(target: saved)
        precondition(restore.tick(origin: system, now: t + 10) == .apply(saved), "stalled first tick must still restore")
        let snapped = CGPoint(x: -424, y: -1100)
        restore.settled(at: snapped)
        precondition(restore.tick(origin: snapped, now: t + 12) == .none)
        precondition(restore.tick(origin: snapped, now: t + 20) == .none)
        precondition(restore.tick(origin: system, now: t + 21) == .report(system))
        restore.rearm(at: saved)
        precondition(restore.tick(origin: system, now: t + 100) == .apply(saved))
        var failed = OriginRestore(target: saved)
        precondition(failed.tick(origin: system, now: t) == .apply(saved))
        precondition(failed.tick(origin: system, now: t + 7) == .none, "failed restore must not overwrite saved position")
        var fresh = OriginRestore(target: nil)
        precondition(fresh.tick(origin: system, now: t) == .report(system))

        let suite = "DisplayWeave.arrangement-test.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let main = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let size = CGSize(width: 1080, height: 1920)
        DisplayArrangement.save(origin: CGPoint(x: -1080, y: 100), size: size, device: "fixture", defaults: defaults, mainBounds: main)
        precondition(DisplayArrangement.origin(for: size, device: "fixture", defaults: defaults, mainBounds: main) == CGPoint(x: -1080, y: 100))
        let rotated = DisplayArrangement.origin(for: CGSize(width: 1920, height: 1080), device: "fixture", defaults: defaults, mainBounds: main)
        precondition(rotated == CGPoint(x: -1920, y: 100), "rotation keeps the chosen side and shared edge")
        defaults.set([0, 0, -1, 1080], forKey: "displayOrigin.bad")
        precondition(DisplayArrangement.origin(for: size, device: "bad", defaults: defaults) == nil)
        DisplayArrangement.save(origin: CGPoint(x: CGFloat.infinity, y: 0), size: size, device: "invalid", defaults: defaults)
        precondition(defaults.object(forKey: "displayOrigin.invalid") == nil)

        // Aligned edges without perpendicular contact belong to another neighbour.
        let lower = CGRect(x: 0, y: 1080, width: 1920, height: 1080)
        let detached = CGRect(x: 1920, y: 1580, width: 1080, height: 1920)
        precondition(DisplayArrangement.inferredMainDisplaySide(of: detached, relativeTo: main) == nil)
        DisplayArrangement.save(origin: detached.origin, size: detached.size, device: "lower-neighbour", defaults: defaults, mainBounds: main)
        precondition(DisplayArrangement.origin(for: CGSize(width: 1920, height: 1080), device: "lower-neighbour", defaults: defaults, mainBounds: main, displays: [main, lower]) == CGPoint(x: 1920, y: 1580))
        // Repair a side stored by the old edge-only check too.
        defaults.set([1920, 1580, 1080, 1920, DisplayArrangement.Side.right.rawValue], forKey: "displayOrigin.old-side")
        precondition(DisplayArrangement.origin(for: CGSize(width: 1920, height: 1080), device: "old-side", defaults: defaults, mainBounds: main, displays: [main, lower]) == CGPoint(x: 1920, y: 1580))
        precondition(DisplayArrangement.inferredMainDisplaySide(of: CGRect(x: 1920, y: 1080, width: 1080, height: 1920), relativeTo: main) == .right, "corner contact remains valid")

        let created = DisplayUnitIdentity(displayID: 30, unit: 2)
        let first = DisplayUnitIdentity(displayID: 10, unit: 2), later = DisplayUnitIdentity(displayID: 20, unit: 3)
        precondition(DisplayUnitCollisionPolicy.plan(created: created, online: [created, first, later], owned: [later, first]) == .rebuild([10, 20]))
        precondition(DisplayUnitCollisionPolicy.plan(created: created, online: [created, first], owned: []) == .unowned(10))
        precondition(DisplayUnitCollisionPolicy.plan(created: created, online: [created, later], owned: [later]) == .none)
        precondition(DisplayUnitCollisionPolicy.plan(created: .init(displayID: 30, unit: UInt32.max), online: [], owned: []) == .unavailable)

        let coordinator = DisplayUnitCoordinator(), a = DisplayPeer(10, 2), b = DisplayPeer(20, 3)
        try coordinator.register(a); try coordinator.register(b)
        do {
            try await coordinator.exclusively {
                try await coordinator.withReleasedPeers([10, 20]) { ids in
                    precondition(ids == [10, 20] && coordinator.identities.isEmpty)
                    b.stopped = true // role/connection ended while the mutation was suspended
                    throw CancellationError()
                }
            }
        } catch is CancellationError {}
        await spin { a.events.count == 2 }
        precondition(a.events == ["release", "rebuild"] && b.events == ["release"], "failure must rebuild live owners only")

        let ordered = DisplayUnitCoordinator(), firstPeer = DisplayPeer(40, 2), lastPeer = DisplayPeer(50, 3)
        let firstRebuild = DisplayGate()
        firstPeer.rebuilding = { await firstRebuild.wait() }
        try ordered.register(firstPeer); try ordered.register(lastPeer)
        try await ordered.exclusively {
            try await ordered.withReleasedPeers([40, 50]) { _ in }
        }
        await spin { firstRebuild.continuation != nil }
        precondition(lastPeer.events == ["release"], "a sibling must finish rebuilding before the next begins")
        firstRebuild.open()
        await spin { lastPeer.events == ["release", "rebuild"] }

        let gate = DisplayGate()
        let holder = Task { try await coordinator.exclusively { await gate.wait() } }
        await spin { gate.continuation != nil }
        var cancelledEntered = false, nextEntered = false
        let cancelled = Task { try await coordinator.exclusively { cancelledEntered = true } }
        await Task.yield()
        cancelled.cancel()
        do { try await cancelled.value; preconditionFailure("cancelled waiter succeeded") } catch is CancellationError {}
        let next = Task { try await coordinator.exclusively { nextEntered = true } }
        await Task.yield()
        precondition(!cancelledEntered && !nextEntered)
        gate.open()
        try await holder.value; try await next.value
        precondition(nextEntered)
        print("Display recovery: delayed origin restore, side-preserving persistence, unit ownership/order, cancellation and sibling restoration PASS")
    }
}

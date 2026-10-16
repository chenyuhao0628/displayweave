import Foundation

struct MacLANRoute: Hashable, Sendable {
    let interfaceName: String
    let direct: Bool
    var wireless: Bool = false
}

struct MacLANCandidateIdentity: Sendable {
    let installID: String
    let route: MacLANRoute
}

/// Session-independent bounds. A Bonjour identity is routing evidence only;
/// secure peer authentication is a separate admission gate.
struct MacLANHandoverPolicy {
    static let recoveryDelays: [Double] = [0.5, 1, 2, 4, 8]
    static let helloTimeout: Double = 5
    private struct Peer {
        var candidate: MacLANRoute?
        var candidateSince: Double = 0
        var transitions: [Double] = []
        var suppressed = false
    }
    private var peers: [String: Peer] = [:]
    var trackedCount: Int { peers.count }

    private func accepts(_ id: String, now: Double) -> Bool {
        !id.isEmpty && id.utf8.count <= 256 && now.isFinite && now >= 0
            && (peers[id] != nil || peers.count < 256)
    }
    func isSuppressed(_ id: String) -> Bool {
        peers[id]?.suppressed ?? (peers.count >= 256)
    }
    mutating func disconnect(_ id: String) {
        guard accepts(id, now: 0) else { return }
        var peer = peers[id] ?? Peer()
        peer.suppressed = true
        peer.candidate = nil
        peers[id] = peer
    }
    mutating func manualConnect(_ id: String) {
        guard accepts(id, now: 0) else { return }
        peers[id] = Peer()
    }
    mutating func clearCandidates() {
        for id in peers.keys { peers[id]?.candidate = nil }
    }
    mutating func upgrade(peer id: String, current: MacLANRoute, candidate: MacLANRoute?,
                          now: Double, enabled: Bool) -> Bool {
        guard accepts(id, now: now) else { return false }
        var state = peers[id] ?? Peer()
        guard enabled, !state.suppressed, !current.direct, let candidate, candidate.direct else {
            state.candidate = nil; peers[id] = state
            return false
        }
        if state.candidate != candidate || now < state.candidateSince {
            state.candidate = candidate; state.candidateSince = now
        }
        peers[id] = state
        guard now - state.candidateSince >= 2,
              state.transitions.last.map({ now - $0 >= 15 }) ?? true else { return false }
        return recover(peer: id, now: now, enabled: enabled)
    }
    mutating func recover(peer id: String, now: Double, enabled: Bool) -> Bool {
        guard enabled, accepts(id, now: now) else { return false }
        var state = peers[id] ?? Peer()
        guard !state.suppressed else { return false }
        state.transitions.removeAll { now - $0 >= 60 }
        guard state.transitions.count < 3 else {
            state.suppressed = true; peers[id] = state
            return false
        }
        state.transitions.append(now)
        state.candidate = nil
        peers[id] = state
        return true
    }
    static func select(peer: String, candidates: [MacLANCandidateIdentity],
                       failed: Set<MacLANRoute>) -> MacLANRoute? {
        candidates.filter { candidate in
            candidate.installID == peer
                && !failed.contains(where: { $0.interfaceName == candidate.route.interfaceName })
        }
            .map(\.route).sorted {
                if $0.direct != $1.direct { return $0.direct }
                if $0.wireless != $1.wireless { return $0.wireless }
                return $0.interfaceName < $1.interfaceName
            }.first
    }
}

/// Owns the stop-before-start sequence and retry count; callbacks run on the UI
/// actor and are invalidated by the controller's peer/role generation.
@MainActor enum MacLANRecoveryRunner {
    enum Outcome { case connected, exhausted, cancelled }
    static func run(cleanup: Task<Void, Never>, current: () -> Bool,
                    pause: (Double) async throws -> Void = { try await Task.sleep(for: .seconds($0)) },
                    attempt: (Int) async -> Bool) async -> Outcome {
        await cleanup.value
        for (index, delay) in MacLANHandoverPolicy.recoveryDelays.enumerated() {
            guard !Task.isCancelled, current() else { return .cancelled }
            do { try await pause(delay) } catch { return .cancelled }
            guard !Task.isCancelled, current() else { return .cancelled }
            if await attempt(index) {
                return !Task.isCancelled && current() ? .connected : .cancelled
            }
        }
        return !Task.isCancelled && current() ? .exhausted : .cancelled
    }
}

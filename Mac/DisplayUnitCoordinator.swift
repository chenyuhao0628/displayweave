import Foundation

struct DisplayUnitIdentity: Equatable {
    let displayID: UInt32
    let unit: UInt32
}

/// Upstream 5de4252 (GPL-3.0), adapted to controller-owned participants instead
/// of a process-global registry of senders. Never release an unowned display.
enum DisplayUnitCollisionPolicy {
    enum Plan: Equatable {
        case none
        case unavailable
        case unowned(UInt32)
        case rebuild([UInt32])
    }

    static func plan(created: DisplayUnitIdentity, online: [DisplayUnitIdentity],
                     owned: [DisplayUnitIdentity]) -> Plan {
        guard created.unit != UInt32.max else { return .unavailable }
        let clashes = online.filter { $0.displayID != created.displayID && $0.unit == created.unit }
        guard !clashes.isEmpty else { return .none }
        let ownedIDs = Set(owned.map(\.displayID))
        if let external = clashes.first(where: { !ownedIDs.contains($0.displayID) }) {
            return .unowned(external.displayID)
        }
        return .rebuild(owned.filter {
            $0.displayID != created.displayID && $0.unit != UInt32.max && $0.unit >= created.unit
        }.sorted {
            $0.unit == $1.unit ? $0.displayID < $1.displayID : $0.unit < $1.unit
        }.map(\.displayID))
    }
}

protocol DisplayUnitParticipant: AnyObject {
    @MainActor var displayUnitIdentity: DisplayUnitIdentity? { get }
    @MainActor func releaseDisplayForRenumbering(expectedID: UInt32) async -> Bool
    @MainActor func resumeAfterDisplayRenumbering() async
}

/// Serializes display mutations, including their asynchronous capture start/
/// stop. Cancellation removes waiters; stop can still retire a sender while a
/// mutation is suspended. Every operation must check its owner after awaits.
@MainActor final class DisplayUnitCoordinator {
    private final class WeakParticipant {
        weak var value: (any DisplayUnitParticipant)?
        init(_ value: any DisplayUnitParticipant) { self.value = value }
    }
    private struct Waiter {
        let id: UUID
        let continuation: CheckedContinuation<Void, Error>
    }
    private var participants: [WeakParticipant] = []
    private var held = false
    private var waiters: [Waiter] = []

    func register(_ participant: any DisplayUnitParticipant) throws {
        participants.removeAll { $0.value == nil }
        guard !participants.contains(where: { $0.value === participant }) else { return }
        guard participants.count < 64 else { throw Self.failure("活动显示会话过多，请先断开部分设备。") }
        participants.append(WeakParticipant(participant))
    }

    func unregister(_ participant: any DisplayUnitParticipant) {
        participants.removeAll { $0.value == nil || $0.value === participant }
    }

    var identities: [DisplayUnitIdentity] { participants.compactMap { $0.value?.displayUnitIdentity } }

    func exclusively<T>(_ operation: @MainActor () async throws -> T) async throws -> T {
        try await acquire()
        defer { release() }
        try Task.checkCancellation()
        return try await operation()
    }

    /// Always resumes affected owners, even if creation fails or is cancelled.
    /// Rebuild in the old unit order, after the initiating operation releases
    /// the lock. Never await the rebuild here: it needs this same lock.
    func withReleasedPeers<T>(_ ids: [UInt32], operation: @MainActor ([UInt32]) async throws -> T) async throws -> T {
        precondition(held)
        var released: [any DisplayUnitParticipant] = []
        var retiredIDs: [UInt32] = []
        defer {
            let owners = released
            Task { @MainActor in
                for owner in owners { await owner.resumeAfterDisplayRenumbering() }
            }
        }
        for id in ids {
            try Task.checkCancellation()
            guard let peer = participants.compactMap(\.value).first(where: { $0.displayUnitIdentity?.displayID == id }) else { continue }
            if await peer.releaseDisplayForRenumbering(expectedID: id) {
                released.append(peer)
                retiredIDs.append(id)
            }
        }
        try Task.checkCancellation()
        return try await operation(retiredIDs)
    }

    private func acquire() async throws {
        try Task.checkCancellation()
        if !held { held = true; return }
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                guard !Task.isCancelled else { continuation.resume(throwing: CancellationError()); return }
                guard waiters.count < 64 else {
                    continuation.resume(throwing: Self.failure("显示配置等待队列已满，请稍后重试。")); return
                }
                waiters.append(Waiter(id: id, continuation: continuation))
            }
        } onCancel: {
            Task { @MainActor in
                guard let index = self.waiters.firstIndex(where: { $0.id == id }) else { return }
                self.waiters.remove(at: index).continuation.resume(throwing: CancellationError())
            }
        }
    }

    private func release() {
        if waiters.isEmpty { held = false }
        else { waiters.removeFirst().continuation.resume() }
    }

    nonisolated static func failure(_ message: String) -> NSError {
        NSError(domain: "DisplayWeave.DisplayRecovery", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}

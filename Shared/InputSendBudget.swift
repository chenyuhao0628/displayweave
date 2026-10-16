import Foundation

/// Admission happens before dispatch, bounding both queued closures and NW sends.
/// A connection replacement invalidates all outstanding tickets atomically.
final class InputSendBudget: @unchecked Sendable {
    struct Ticket: Hashable { let generation: UInt64; let sequence: UInt64 }
    enum Admission: Equatable { case accepted(Ticket), overflow(UInt64), unavailable }
    private let lock = NSLock()
    private let limit: Int
    private var epoch: UInt64 = 0
    private var sequence: UInt64 = 0
    private var accepting = false
    private var pending: Set<Ticket> = []

    init(limit: Int = 64) { self.limit = max(1, limit) }
    var generation: UInt64 { lock.lock(); defer { lock.unlock() }; return epoch }
    var pendingCount: Int { lock.lock(); defer { lock.unlock() }; return pending.count }

    @discardableResult func reset(accepting: Bool) -> UInt64 {
        lock.lock(); defer { lock.unlock() }
        epoch &+= 1
        self.accepting = accepting
        pending.removeAll(keepingCapacity: true)
        return epoch
    }

    func reserve(expectedGeneration: UInt64? = nil) -> Admission {
        lock.lock(); defer { lock.unlock() }
        guard accepting, expectedGeneration == nil || expectedGeneration == epoch else { return .unavailable }
        guard pending.count < limit else { accepting = false; return .overflow(epoch) }
        sequence &+= 1
        let ticket = Ticket(generation: epoch, sequence: sequence)
        pending.insert(ticket)
        return .accepted(ticket)
    }

    @discardableResult func complete(_ ticket: Ticket) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard epoch == ticket.generation else { return false }
        return pending.remove(ticket) != nil
    }
}

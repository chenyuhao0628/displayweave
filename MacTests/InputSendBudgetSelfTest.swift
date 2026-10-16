import Foundation

@main struct InputSendBudgetSelfTest {
    static func main() {
        let budget = InputSendBudget(limit: 2)
        precondition(budget.reserve() == .unavailable)
        let old = budget.reset(accepting: true)
        guard case .accepted(let first) = budget.reserve(expectedGeneration: old),
              case .accepted = budget.reserve(expectedGeneration: old) else { fatalError("admission") }
        precondition(budget.reserve() == .overflow(old))
        precondition(budget.reserve() == .unavailable, "overflow must schedule at most one disconnect")
        let fresh = budget.reset(accepting: true)
        precondition(!budget.complete(first), "stale completion changed new budget")
        precondition(budget.reserve(expectedGeneration: old) == .unavailable)
        guard case .accepted(let next) = budget.reserve(expectedGeneration: fresh) else { fatalError("new admission") }
        precondition(budget.complete(next))
        precondition(!budget.complete(next))
        budget.reset(accepting: false)
        precondition(budget.reserve() == .unavailable)
        budget.reset(accepting: true)
        DispatchQueue.concurrentPerform(iterations: 1000) { _ in
            if case .accepted(let token) = budget.reserve() { _ = budget.complete(token) }
        }
        precondition(budget.pendingCount <= 2)
        print("Input send budget: queued + network bounds, overflow latch and stale generation isolation PASS")
    }
}

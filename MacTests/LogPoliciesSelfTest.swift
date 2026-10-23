import Foundation

@main struct LogPoliciesSelfTest {
    static func main() {
        var errors = ThrottledLogPolicy<Int32>()
        precondition(errors.record(-12902, at: 0) == .report(.init(detail: -12902, count: 1)))
        precondition(errors.record(-12900, at: 0.1) == .schedule(after: 0.9))
        for _ in 0..<600 { precondition(errors.record(-12902, at: 0.5) == .none) }
        precondition(errors.flush(at: 1) == .init(detail: -12902, count: 601))
        precondition(errors.flush(at: 2) == nil)
        precondition(errors.record(0, at: 3) == .report(.init(detail: 0, count: 1)))
        var types = UnknownControlTypeLogPolicy(capacity: 2)
        precondition(types.record("a") == .logType("a"))
        precondition(types.record("a") == .none)
        precondition(types.record("b") == .logType("b"))
        precondition(types.record("c") == .logSuppression(limit: 2))
        for i in 0..<1_000 { precondition(types.record("unknown-\(i)") == .none) }
        print("Log policies: per-error aggregation, one flush, bounded unknown-control types PASS")
    }
}

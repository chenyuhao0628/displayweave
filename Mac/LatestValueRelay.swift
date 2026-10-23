import Foundation

/// One scheduled/in-flight delivery and one replaceable pending value. Tokens
/// survive resets so completions from a retired session cannot drain a new one.
final class LatestValueRelay<Value>: @unchecked Sendable {
    struct Token: Equatable { fileprivate let id: UInt64 }
    struct Metrics {
        var offered = 0
        var coalesced = 0
        var completed = 0
        var maxWaitMs: Double = 0
    }

    private let lock = NSLock()
    private var nextID: UInt64 = 0
    private var epoch: UInt64 = 0
    private var active: Token?
    private var pending: (value: Value, time: TimeInterval)?
    private var metrics = Metrics()

    func offer(_ value: Value) -> Token? {
        lock.lock(); defer { lock.unlock() }
        metrics.offered += 1
        if pending != nil { metrics.coalesced += 1 }
        pending = (value, ProcessInfo.processInfo.systemUptime)
        return scheduleLocked()
    }

    func take(_ token: Token) -> Value? {
        lock.lock(); defer { lock.unlock() }
        guard active == token, let value = pending else { return nil }
        pending = nil
        metrics.maxWaitMs = max(metrics.maxWaitMs,
            (ProcessInfo.processInfo.systemUptime - value.time) * 1_000)
        return value.value
    }

    func complete(_ token: Token) -> Token? {
        lock.lock(); defer { lock.unlock() }
        guard active == token else { return nil }
        active = nil
        metrics.completed += 1
        return scheduleLocked()
    }

    func isCurrent(_ token: Token) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return active == token
    }

    func reset() {
        lock.lock(); defer { lock.unlock() }
        epoch &+= 1
        active = nil
        pending = nil
        metrics = Metrics()
    }

    var generation: UInt64 {
        lock.lock(); defer { lock.unlock() }
        return epoch
    }

    func takeMetrics() -> Metrics {
        lock.lock(); defer { lock.unlock() }
        let result = metrics
        metrics = Metrics()
        return result
    }

    private func scheduleLocked() -> Token? {
        guard active == nil, pending != nil else { return nil }
        nextID &+= 1
        let token = Token(id: nextID)
        active = token
        return token
    }
}

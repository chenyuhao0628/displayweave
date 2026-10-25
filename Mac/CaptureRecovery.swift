import Foundation

/// A successful submission is not a successful output. Keep the failure budget
/// across encoder replacements until five seconds of healthy output occur.
struct EncoderFailureRecovery {
    enum Action: Equatable { case retry, rebuild, exhausted }
    private(set) var rebuilds = 0
    private var transientFailures = 0
    private var healthySince: TimeInterval?

    mutating func failed(transient: Bool) -> Action {
        healthySince = nil
        transientFailures += 1
        if transient && transientFailures <= 3 { return .retry }
        guard rebuilds < 2 else { return .exhausted }
        rebuilds += 1
        transientFailures = 0
        return .rebuild
    }

    mutating func producedOutput(at now: TimeInterval) {
        guard now.isFinite else { return }
        if healthySince == nil || now < healthySince! { healthySince = now }
        if now - healthySince! >= 5 {
            rebuilds = 0
            transientFailures = 0
        }
    }
}

/// Latest-frame replay after pre-encode drops, adapted from upstream c8b2417
/// (GPL-3.0). One cached frame and one deadline, owned by the capture generation.
struct CaptureFrameReplay<Frame> {
    private(set) var generation: UInt64 = 0
    private(set) var latest: Frame?
    private(set) var deadline: TimeInterval?
    private var active = false

    mutating func begin() -> UInt64 {
        retire()
        active = true
        return generation
    }

    mutating func retire() {
        generation &+= 1
        active = false
        latest = nil
        deadline = nil
    }

    @discardableResult
    mutating func offer(_ frame: Frame, generation: UInt64) -> Bool {
        guard active, generation == self.generation else { return false }
        latest = frame
        return true
    }

    mutating func dropped(at now: TimeInterval) {
        guard active, latest != nil else { return }
        deadline = now + 0.030
    }

    mutating func takeDue(at now: TimeInterval, ready: Bool) -> Frame? {
        guard active, let deadline, now >= deadline else { return nil }
        guard ready else { self.deadline = now + 0.030; return nil }
        self.deadline = nil
        return latest
    }

    mutating func submitted() { deadline = nil }
}

/// Sleep/lock does not spend recovery attempts. A live display needs only a
/// new SCStream; rebuilding it would disrupt sibling displays (ceebb2d/09e717e).
struct CaptureRecoveryPolicy {
    enum Action: Equatable { case waitForConsole, reattach, rebuild, exhausted }
    private(set) var failures = 0
    private(set) var wrongSourceRecoveries = 0
    private var attemptPending = false

    func action(consoleAvailable: Bool, displayOnline: Bool) -> Action {
        guard consoleAvailable else { return .waitForConsole }
        guard failures < 5 else { return .exhausted }
        return displayOnline ? .reattach : .rebuild
    }

    mutating func beginAttempt() { attemptPending = true }

    /// A successful startCapture call is not proof of recovered video. Keep
    /// the attempt pending until a valid frame arrives or the stream stops.
    /// Delegate and task completion may both report the same failed attempt.
    mutating func finished(succeeded: Bool, consoleAvailable: Bool) {
        if succeeded { failures = 0 }
        else if attemptPending && consoleAvailable { failures += 1 }
        attemptPending = false
    }

    mutating func recoverWrongSource() -> Bool {
        guard wrongSourceRecoveries < 3 else { return false }
        wrongSourceRecoveries += 1
        return true
    }

    static func honorsSystemStop(userStopped: Bool, consoleInteractive: Bool) -> Bool {
        userStopped && consoleInteractive
    }
}

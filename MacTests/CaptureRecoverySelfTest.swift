import Foundation
import CoreGraphics

@main struct CaptureRecoverySelfTest {
    static func main() {
        var replay = CaptureFrameReplay<Int>()
        let old = replay.begin()
        replay.offer(1, generation: old)
        replay.dropped(at: 0)
        precondition(replay.takeDue(at: 0.029, ready: true) == nil)
        replay.offer(2, generation: old)
        replay.dropped(at: 0.020)
        precondition(replay.takeDue(at: 0.040, ready: true) == nil)
        precondition(replay.takeDue(at: 0.051, ready: false) == nil)
        precondition(replay.takeDue(at: 0.082, ready: true) == 2)
        precondition(replay.takeDue(at: 10, ready: true) == nil, "replay only once after pressure drains")
        replay.dropped(at: 11)
        replay.submitted()
        precondition(replay.takeDue(at: 12, ready: true) == nil)
        let fresh = replay.begin()
        precondition(!replay.offer(99, generation: old) && replay.latest == nil)
        replay.offer(3, generation: fresh)
        replay.dropped(at: 13)
        replay.retire()
        precondition(replay.latest == nil && replay.takeDue(at: 14, ready: true) == nil)

        var recovery = CaptureRecoveryPolicy()
        for _ in 0..<100 {
            precondition(recovery.action(consoleAvailable: false, displayOnline: true) == .waitForConsole)
            recovery.beginAttempt()
            recovery.finished(succeeded: false, consoleAvailable: false)
        }
        precondition(recovery.failures == 0)
        precondition(recovery.action(consoleAvailable: true, displayOnline: true) == .reattach)
        precondition(recovery.action(consoleAvailable: true, displayOnline: false) == .rebuild)
        for expected in 1...5 {
            recovery.beginAttempt()
            recovery.finished(succeeded: false, consoleAvailable: true)
            recovery.finished(succeeded: false, consoleAvailable: true)
            precondition(recovery.failures == expected, "delegate and completion count one failed round")
        }
        precondition(recovery.action(consoleAvailable: true, displayOnline: true) == .exhausted)
        recovery.finished(succeeded: true, consoleAvailable: true)
        precondition(recovery.failures == 0)
        for _ in 0..<3 { precondition(recovery.recoverWrongSource()) }
        precondition(!recovery.recoverWrongSource())
        precondition(CaptureRecoveryPolicy.honorsSystemStop(userStopped: true, consoleInteractive: true))
        precondition(!CaptureRecoveryPolicy.honorsSystemStop(userStopped: true, consoleInteractive: false))

        var encoder = EncoderFailureRecovery()
        precondition(encoder.failed(transient: false) == .rebuild)
        encoder.producedOutput(at: 0)
        precondition(encoder.failed(transient: false) == .rebuild, "one good frame does not refill the budget")
        precondition(encoder.failed(transient: false) == .exhausted)
        encoder.producedOutput(at: 1)
        encoder.producedOutput(at: 5.9)
        precondition(encoder.rebuilds == 2)
        encoder.producedOutput(at: 6)
        precondition(encoder.failed(transient: false) == .rebuild, "healthy output restores recovery budget")
        var busy = EncoderFailureRecovery()
        var attempts = 0
        while busy.failed(transient: true) != .exhausted { attempts += 1; precondition(attempts < 12) }
        precondition(attempts == 11, "persistent busy/output drops must also terminate")

        var check = CaptureSourceCheck()
        let own = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let other = CGRect(x: -1920, y: 0, width: 1920, height: 1080)
        let now = Date(timeIntervalSinceReferenceDate: 0)
        precondition(!check.frame(screenRect: other, expected: own, now: now))
        precondition(!check.frame(screenRect: other, expected: own, now: now + 1))
        precondition(check.frame(screenRect: other, expected: own, now: now + 1.5))
        precondition(!check.frame(screenRect: other, expected: own, now: now + 1.6))
        precondition(!check.frame(screenRect: own, expected: own, now: now + 2))
        precondition(!check.frame(screenRect: other, expected: own, now: now + 3))
        precondition(!check.frame(screenRect: .zero, expected: own, now: now + 20))
        print("Capture recovery: latest final-frame replay, generation retirement, sleep budget, live-display reattach and source mismatch PASS")
    }
}

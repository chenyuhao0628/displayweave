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

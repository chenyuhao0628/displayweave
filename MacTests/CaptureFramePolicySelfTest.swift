import CoreGraphics
import CoreMedia
import Foundation

private func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() { fatalError(message) }
}

@main
struct CaptureFramePolicySelfTest {
    static func main() {
        expect(CaptureStaticFramePolicy.defaultQueueDepth == 4,
               "SCStream queueDepth should be tightened to 4")

        // 1. Dirty rects parsing
        expect(CaptureStaticFramePolicy.hasNonEmptyDirtyRects(nil) == true,
               "missing dirtyRects attachment must fail-safe to dirty")
        expect(CaptureStaticFramePolicy.hasNonEmptyDirtyRects([] as [Any]) == false,
               "empty dirtyRects array indicates static frame")

        let zeroDict = CGRect.zero.dictionaryRepresentation as NSDictionary
        let nonEmptyDict = CGRect(x: 10, y: 20, width: 100, height: 50).dictionaryRepresentation as NSDictionary
        expect(CaptureStaticFramePolicy.hasNonEmptyDirtyRects([zeroDict]) == false,
               "zero-area CGRect dictionary is static")
        expect(CaptureStaticFramePolicy.hasNonEmptyDirtyRects([zeroDict, nonEmptyDict]) == true,
               "any positive-area CGRect dictionary marks frame dirty")

        let zeroVal = NSValue(rect: .zero)
        let nonEmptyVal = NSValue(rect: NSRect(x: 0, y: 0, width: 4, height: 4))
        expect(CaptureStaticFramePolicy.hasNonEmptyDirtyRects([zeroVal]) == false,
               "zero-area NSValue rect is static")
        expect(CaptureStaticFramePolicy.hasNonEmptyDirtyRects([zeroVal, nonEmptyVal]) == true,
               "positive-area NSValue rect marks frame dirty")

        // 2. Static frame gate invariants
        var gate = CaptureStaticFrameGate(settlingTailFrames: 1, maxStaticRefreshInterval: 0.5)
        // Before the first frame in the current config is encoded, static frames MUST NOT be skipped.
        expect(gate.shouldEncodeFrame(hasDirtyRects: false, requiresKeyframe: false, nowUptime: 1.0) == true,
               "must never skip before first frame of current config is encoded")
        expect(gate.shouldEncodeFrame(hasDirtyRects: false, requiresKeyframe: false, nowUptime: 1.016) == true,
               "still must not skip until markFrameEncoded() is called")

        gate.markFrameEncoded()
        // Active motion frame arms post-motion settled crisp refresh (at t=1.033).
        expect(gate.shouldEncodeFrame(hasDirtyRects: true, requiresKeyframe: false, nowUptime: 1.033) == true,
               "dirty motion frame is always admitted and arms crisp refresh")
        // First clean frame after dirty frame uses the 1 settling tail frame.
        expect(gate.shouldEncodeFrame(hasDirtyRects: false, requiresKeyframe: false, nowUptime: 1.049) == true,
               "first clean frame after dirty frame is admitted as settling tail frame")
        // Subsequent static frames before crispRefreshDelay (180ms from 1.033 -> 1.213) are skipped.
        expect(gate.shouldEncodeFrame(hasDirtyRects: false, requiresKeyframe: false, nowUptime: 1.066) == false,
               "static frame after settling tail frame before crisp refresh window is skipped")
        expect(gate.shouldEncodeFrame(hasDirtyRects: false, requiresKeyframe: false, nowUptime: 1.200) == false,
               "static frame at +167ms (< 180ms crisp refresh delay) is still skipped")
        expect(gate.skippedStaticFrames == 2, "skipped static frame counter increments")

        // At +185ms (>= 180ms after motion at 1.033), exactly ONE settled crisp text refresh frame is admitted!
        let crispDecision = gate.evaluate(hasDirtyRects: false, requiresKeyframe: false, nowUptime: 1.218)
        expect(crispDecision.shouldEncode && crispDecision.isSettledCrispRefresh,
               "~180ms after motion settles, gate emits one settled crisp text refresh frame")
        expect(gate.shouldEncodeFrame(hasDirtyRects: false, requiresKeyframe: false, nowUptime: 1.250) == false,
               "settled crisp refresh fires only once per motion burst")

        // Keyframe request immediately overrides static skip.
        expect(gate.shouldEncodeFrame(hasDirtyRects: false, requiresKeyframe: true, nowUptime: 1.300) == true,
               "pending/in-flight keyframe request must bypass static skip immediately")
        // And resets settling tail frame.
        expect(gate.shouldEncodeFrame(hasDirtyRects: false, requiresKeyframe: false, nowUptime: 1.316) == true,
               "settling tail frame follows forced keyframe")
        expect(gate.shouldEncodeFrame(hasDirtyRects: false, requiresKeyframe: false, nowUptime: 1.332) == false,
               "static skip resumes after settling tail frame")

        // Timer-driven crisp refresh when ScreenCaptureKit stops emitting static callbacks after motion:
        expect(gate.shouldEncodeFrame(hasDirtyRects: true, requiresKeyframe: false, nowUptime: 1.350) == true,
               "second motion burst arms timer crisp refresh")
        expect(gate.shouldEncodeFrame(hasDirtyRects: false, requiresKeyframe: false, nowUptime: 1.366) == true,
               "settling tail frame after second motion burst")
        expect(gate.pollTimerCrispRefresh(nowUptime: 1.500) == false,
               "pollTimerCrispRefresh waits until full 180ms settle window elapses")
        expect(gate.pollTimerCrispRefresh(nowUptime: 1.535) == true,
               "pollTimerCrispRefresh triggers settled crisp refresh at >= 180ms")
        expect(gate.pollTimerCrispRefresh(nowUptime: 1.550) == false,
               "pollTimerCrispRefresh disarms after firing once")

        // Keepalive refresh fires once 0.5s elapses since last admitted frame (1.535 + 0.5 = 2.035).
        let keepaliveDecision = gate.evaluate(hasDirtyRects: false, requiresKeyframe: false, nowUptime: 2.040)
        expect(keepaliveDecision.shouldEncode && !keepaliveDecision.isSettledCrispRefresh,
               "periodic static keepalive admits normal refresh frame after 500ms")
        expect(gate.shouldEncodeFrame(hasDirtyRects: false, requiresKeyframe: false, nowUptime: 2.055) == false,
               "static skip resumes immediately after keepalive frame")

        // Resetting for a new configuration requires encoding a fresh initial frame again.
        gate.resetForNewConfiguration()
        expect(gate.shouldEncodeFrame(hasDirtyRects: false, requiresKeyframe: false, nowUptime: 2.080) == true,
               "resetForNewConfiguration forces initial frame admission on static desktop")

        // 3. CaptureTimestampPolicy clock-domain conversion
        let wallMs: Double = 1_700_000_000_500.0
        expect(CaptureTimestampPolicy.wallClockCaptureMs(
            nowWallMs: wallMs, displayTimeHostSeconds: 100.000, nowHostSeconds: 100.006) == 1_700_000_000_494,
            "6ms elapsed host time subtracts 6ms from wall-clock timestamp")
        expect(CaptureTimestampPolicy.wallClockCaptureMs(
            nowWallMs: wallMs, displayTimeHostSeconds: 100.010, nowHostSeconds: 100.000) == 1_700_000_000_500,
            "future displayTime clamps to 0ms lookback")
        expect(CaptureTimestampPolicy.wallClockCaptureMs(
            nowWallMs: wallMs, displayTimeHostSeconds: 90.000, nowHostSeconds: 100.000) == 1_700_000_000_250,
            "stale displayTime lookback is bounded to 250ms")
        expect(CaptureTimestampPolicy.wallClockCaptureMs(
            nowWallMs: wallMs, displayTimeHostSeconds: nil, nowHostSeconds: 100.000) == 1_700_000_000_500,
            "missing displayTime falls back to current wall-clock ms")

        let nowTicks = mach_absolute_time()
        let derivedMs = CaptureTimestampPolicy.captureTimestampMs(from: NSNumber(value: nowTicks))
        let currentWallMs = Int64(Date().timeIntervalSince1970 * 1000)
        expect(abs(derivedMs - currentWallMs) <= 50,
               "live mach_absolute_time conversion stays aligned with wall-clock ms")

        print("CaptureFramePolicySelfTest PASS")
    }
}

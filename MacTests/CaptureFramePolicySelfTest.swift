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
        // First clean frame after markFrameEncoded uses the 1 settling tail frame.
        expect(gate.shouldEncodeFrame(hasDirtyRects: false, requiresKeyframe: false, nowUptime: 1.033) == true,
               "first clean frame after dirty/initial frame is admitted as settling tail frame")
        // Subsequent static frames within 500ms are skipped.
        expect(gate.shouldEncodeFrame(hasDirtyRects: false, requiresKeyframe: false, nowUptime: 1.050) == false,
               "static frame after settling tail frame within keepalive window is skipped")
        expect(gate.shouldEncodeFrame(hasDirtyRects: false, requiresKeyframe: false, nowUptime: 1.200) == false,
               "static frame at +167ms is still skipped")
        expect(gate.skippedStaticFrames == 2, "skipped static frame counter increments")

        // Keyframe request immediately overrides static skip.
        expect(gate.shouldEncodeFrame(hasDirtyRects: false, requiresKeyframe: true, nowUptime: 1.210) == true,
               "pending/in-flight keyframe request must bypass static skip immediately")
        // And resets settling tail frame.
        expect(gate.shouldEncodeFrame(hasDirtyRects: false, requiresKeyframe: false, nowUptime: 1.226) == true,
               "settling tail frame follows forced keyframe")
        expect(gate.shouldEncodeFrame(hasDirtyRects: false, requiresKeyframe: false, nowUptime: 1.242) == false,
               "static skip resumes after settling tail frame")

        // Keepalive refresh fires once 0.5s elapses since last admitted frame (1.226 + 0.5 = 1.726).
        expect(gate.shouldEncodeFrame(hasDirtyRects: false, requiresKeyframe: false, nowUptime: 1.730) == true,
               "periodic static keepalive admits one refresh frame after 500ms")
        expect(gate.shouldEncodeFrame(hasDirtyRects: false, requiresKeyframe: false, nowUptime: 1.746) == false,
               "static skip resumes immediately after keepalive frame")

        // Resetting for a new configuration requires encoding a fresh initial frame again.
        gate.resetForNewConfiguration()
        expect(gate.shouldEncodeFrame(hasDirtyRects: false, requiresKeyframe: false, nowUptime: 1.760) == true,
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

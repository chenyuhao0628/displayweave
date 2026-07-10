import Foundation

func assertEqual(_ expected: Int, _ actual: Int, _ message: String) {
    if expected != actual {
        fatalError("\(message): expected \(expected), got \(actual)")
    }
}

func assertEqual(_ expected: [Int], _ actual: [Int], _ message: String) {
    if expected != actual {
        fatalError("\(message): expected \(expected), got \(actual)")
    }
}

func assertEqual(_ expected: String?, _ actual: String?, _ message: String) {
    if expected != actual {
        fatalError("\(message): expected \(String(describing: expected)), got \(String(describing: actual))")
    }
}

@main
struct RefreshRatePolicySelfTest {
    static func main() {
        assertEqual(30, RefreshRatePolicy.sanitize(24), "low fps values clamp to 30")
        assertEqual(60, RefreshRatePolicy.sanitize(59), "near-60 values bucket to 60")
        assertEqual(90, RefreshRatePolicy.sanitize(89), "near-90 values bucket to 90")
        assertEqual(120, RefreshRatePolicy.sanitize(144), "high values cap at 120")

        assertEqual(90, RefreshRatePolicy.selected(deviceMaxFps: 120, userSelectedFps: 90),
                    "user setting can limit a 120Hz device")
        assertEqual(60, RefreshRatePolicy.selected(deviceMaxFps: 60, userSelectedFps: 120),
                    "device max fps limits a 120fps user setting")
        assertEqual(120, RefreshRatePolicy.selected(deviceMaxFps: 120, userSelectedFps: nil),
                    "auto mode uses device max fps")

        assertEqual([120, 60], RefreshRatePolicy.attemptOrder(requestedFps: 120),
                    "120Hz virtual display attempts fall back to 60")
        assertEqual([90, 60], RefreshRatePolicy.attemptOrder(requestedFps: 90),
                    "90Hz virtual display attempts fall back to 60")
        assertEqual([60], RefreshRatePolicy.attemptOrder(requestedFps: 60),
                    "60Hz virtual display does not retry itself")
        assertEqual("system reported 60Hz after accepting 120Hz",
                    RefreshRatePolicy.fallbackReason(requestedFps: 120,
                                                     appliedFps: 120,
                                                     actualFps: 60),
                    "silent system refresh clamp has an explicit reason")
        assertEqual(nil,
                    RefreshRatePolicy.fallbackReason(requestedFps: 120,
                                                     appliedFps: 120,
                                                     actualFps: 120),
                    "matching requested/actual refresh needs no fallback reason")

        assertEqual(30, RefreshRatePolicy.captureIntervalTimescale(fps: 30),
                    "30fps capture interval uses timescale 30")
        assertEqual(60, RefreshRatePolicy.captureIntervalTimescale(fps: 60),
                    "60fps capture interval uses timescale 60")
        assertEqual(90, RefreshRatePolicy.captureIntervalTimescale(fps: 90),
                    "90fps capture interval uses timescale 90")
        assertEqual(120, RefreshRatePolicy.captureIntervalTimescale(fps: 120),
                    "120fps capture interval uses timescale 120")

        print("RefreshRatePolicySelfTest PASS")
    }
}

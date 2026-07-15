import Foundation

enum RefreshRatePolicy {
    static let fallbackFps = 60

    static func sanitize(_ fps: Int) -> Int {
        if fps >= 110 { return 120 }
        if fps >= 80 { return 90 }
        if fps >= 45 { return 60 }
        return 30
    }

    static func selected(deviceMaxFps: Int, userSelectedFps: Int?) -> Int {
        let device = sanitize(deviceMaxFps)
        let user = userSelectedFps.map(sanitize) ?? device
        return min(device, user)
    }

    static func attemptOrder(requestedFps: Int) -> [Int] {
        let requested = sanitize(requestedFps)
        guard requested != fallbackFps else { return [fallbackFps] }
        return [requested, fallbackFps]
    }

    static func captureIntervalTimescale(fps: Int) -> Int {
        sanitize(fps)
    }

    static func decoderDowngrade(currentFps: Int, reportedMaxFps: Int) -> Int? {
        let current = sanitize(currentFps)
        let reported = sanitize(reportedMaxFps)
        return reported < current ? reported : nil
    }

    static func fallbackReason(requestedFps: Int, appliedFps: Int,
                               actualFps: Int) -> String? {
        if appliedFps != requestedFps {
            return "CGVirtualDisplay rejected \(requestedFps)Hz; retried \(appliedFps)Hz"
        }
        if actualFps != requestedFps {
            return "system reported \(actualFps)Hz after accepting \(requestedFps)Hz"
        }
        return nil
    }
}

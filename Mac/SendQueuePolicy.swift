import Foundation

enum SendQueuePolicy {
    struct DropDecision: Equatable {
        var shouldDrop: Bool
        var droppedFrames: Int
        var reason: FrameDropReason?
        var forceKeyframe: Bool
    }
    /// Candidate low-latency budgets pending physical-device A/B validation.
    static func budget(quality: StreamQuality) -> Int {
        switch quality {
        case .gaming: return 1
        case .low, .balanced: return 2
        case .high: return 3
        }
    }

    /// VideoToolbox is asynchronous. At 90/120 fps one frame can still be in
    /// flight when the next capture arrives, so a depth of one deterministically
    /// halves cadence whenever encode latency exceeds one frame interval.
    static func encodeBudget(fps: Int) -> Int {
        fps >= 90 ? 2 : 1
    }

    static func shouldDrop(pendingSends: Int, pendingEncodes: Int = 0,
                           sendBudget: Int, encodeBudget: Int) -> Bool {
        max(pendingSends, 0) >= max(sendBudget, 1)
            || max(pendingEncodes, 0) >= max(encodeBudget, 1)
    }

    static func decision(pendingSends: Int, pendingEncodes: Int = 0,
                         sendBudget: Int, encodeBudget: Int,
                         currentDroppedFrames: Int) -> DropDecision {
        let drop = shouldDrop(
            pendingSends: pendingSends,
            pendingEncodes: pendingEncodes,
            sendBudget: sendBudget,
            encodeBudget: encodeBudget)
        let reason: FrameDropReason? = drop ? .preEncodeCaptureSkip : nil
        return DropDecision(shouldDrop: drop,
                            droppedFrames: currentDroppedFrames + (drop ? 1 : 0),
                            reason: reason,
                            forceKeyframe: reason?.requiresKeyframe == true)
    }
}

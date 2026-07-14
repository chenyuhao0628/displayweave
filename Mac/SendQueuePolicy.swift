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

    static func shouldDrop(pendingSends: Int, pendingEncodes: Int = 0,
                           budget: Int) -> Bool {
        max(pendingSends, 0) + max(pendingEncodes, 0) >= max(budget, 1)
    }

    static func decision(pendingSends: Int, pendingEncodes: Int = 0, budget: Int,
                         currentDroppedFrames: Int) -> DropDecision {
        let drop = shouldDrop(
            pendingSends: pendingSends,
            pendingEncodes: pendingEncodes,
            budget: budget)
        let reason: FrameDropReason? = drop ? .preEncodeCaptureSkip : nil
        return DropDecision(shouldDrop: drop,
                            droppedFrames: currentDroppedFrames + (drop ? 1 : 0),
                            reason: reason,
                            forceKeyframe: reason?.requiresKeyframe == true)
    }
}

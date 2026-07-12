import Foundation

enum SendQueuePolicy {
    struct DropDecision: Equatable {
        var shouldDrop: Bool
        var droppedFrames: Int
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

    static func shouldDrop(pendingSends: Int, budget: Int) -> Bool {
        pendingSends >= max(budget, 1)
    }

    static func decision(pendingSends: Int, budget: Int,
                         currentDroppedFrames: Int) -> DropDecision {
        let drop = shouldDrop(pendingSends: pendingSends, budget: budget)
        return DropDecision(shouldDrop: drop,
                            droppedFrames: currentDroppedFrames + (drop ? 1 : 0),
                            forceKeyframe: drop)
    }
}

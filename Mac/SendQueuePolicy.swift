import Foundation

enum SendQueuePolicy {
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
}

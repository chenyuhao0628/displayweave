import Foundation

/// Counts asynchronous work per immutable owner generation.
struct GenerationWorkCounter {
    private var counts: [UInt64: Int] = [:]
    private(set) var peak = 0
    private(set) var unmatchedCompletions = 0

    mutating func begin(generation: UInt64) {
        let next = counts[generation, default: 0] + 1
        counts[generation] = next
        peak = max(peak, next)
    }

    @discardableResult
    mutating func complete(generation: UInt64) -> Bool {
        guard let current = counts[generation], current > 0 else {
            unmatchedCompletions += 1
            return false
        }
        if current == 1 {
            counts.removeValue(forKey: generation)
        } else {
            counts[generation] = current - 1
        }
        return true
    }

    func count(generation: UInt64) -> Int {
        counts[generation, default: 0]
    }
}

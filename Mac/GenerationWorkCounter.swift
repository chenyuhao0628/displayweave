import Foundation

/// Counts asynchronous work per immutable owner generation.
struct GenerationWorkCounter {
    typealias WorkID = UInt64

    private var activeWork: [UInt64: Set<WorkID>] = [:]
    private var nextWorkID: WorkID = 0
    private(set) var peak = 0
    private(set) var unmatchedCompletions = 0

    @discardableResult
    mutating func begin(generation: UInt64) -> WorkID {
        nextWorkID &+= 1
        if nextWorkID == 0 {
            nextWorkID &+= 1
        }
        let workID = nextWorkID
        activeWork[generation, default: []].insert(workID)
        peak = max(peak, activeWork[generation]?.count ?? 0)
        return workID
    }

    @discardableResult
    mutating func complete(generation: UInt64, workID: WorkID) -> Bool {
        guard var work = activeWork[generation], work.remove(workID) != nil else {
            unmatchedCompletions += 1
            return false
        }
        if work.isEmpty {
            activeWork.removeValue(forKey: generation)
        } else {
            activeWork[generation] = work
        }
        return true
    }

    func count(generation: UInt64) -> Int {
        activeWork[generation]?.count ?? 0
    }

    mutating func discard(generation: UInt64) {
        activeWork.removeValue(forKey: generation)
    }
}

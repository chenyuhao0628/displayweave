import Foundation

@main
enum SendQueuePolicySelfTest {
    static func main() {
        precondition(SendQueuePolicy.budget(quality: .gaming) == 1)
        precondition(SendQueuePolicy.budget(quality: .balanced) == 2)
        precondition(SendQueuePolicy.budget(quality: .high) == 3)
        precondition(!SendQueuePolicy.shouldDrop(pendingSends: 0, budget: 1))
        precondition(SendQueuePolicy.shouldDrop(pendingSends: 1, budget: 1))
        precondition(SendQueuePolicy.shouldDrop(pendingSends: 3, budget: 3))
        precondition(SendQueuePolicy.shouldDrop(
            pendingSends: 0, pendingEncodes: 3, budget: 3))
        precondition(SendQueuePolicy.shouldDrop(
            pendingSends: 1, pendingEncodes: 2, budget: 3))
        precondition(!SendQueuePolicy.shouldDrop(
            pendingSends: 1, pendingEncodes: 1, budget: 3))
        let decision = SendQueuePolicy.decision(
            pendingSends: 1, pendingEncodes: 1, budget: 2,
            currentDroppedFrames: 4)
        precondition(decision.shouldDrop && decision.droppedFrames == 5)
        precondition(decision.reason == .preEncodeCaptureSkip)
        precondition(!decision.forceKeyframe)

        var work = GenerationWorkCounter()
        work.begin(generation: 1)
        work.begin(generation: 1)
        precondition(work.count(generation: 1) == 2 && work.peak == 2)
        work.begin(generation: 2)
        precondition(work.count(generation: 2) == 1)
        precondition(work.complete(generation: 1))
        precondition(work.count(generation: 2) == 1,
                     "old completion must not decrement current generation")
        precondition(!work.complete(generation: 3))
        precondition(work.unmatchedCompletions == 1)
        print("SendQueuePolicySelfTest PASS")
    }
}

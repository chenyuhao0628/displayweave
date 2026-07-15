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
        let workA = work.begin(generation: 1)
        let workB = work.begin(generation: 1)
        precondition(work.count(generation: 1) == 2 && work.peak == 2)
        let workC = work.begin(generation: 2)
        precondition(work.count(generation: 2) == 1)
        precondition(work.complete(generation: 1, workID: workA))
        precondition(work.count(generation: 2) == 1,
                     "old completion must not decrement current generation")
        precondition(!work.complete(generation: 1, workID: workA),
                     "duplicate completion must not consume another work item")
        precondition(work.count(generation: 1) == 1)
        precondition(work.complete(generation: 1, workID: workB))
        precondition(work.complete(generation: 2, workID: workC))
        precondition(!work.complete(generation: 3, workID: workC))
        precondition(work.unmatchedCompletions == 2)
        let abandoned = work.begin(generation: 4)
        work.discard(generation: 4)
        precondition(work.count(generation: 4) == 0)
        precondition(!work.complete(generation: 4, workID: abandoned),
                     "discarded generation must reject late completion")
        print("SendQueuePolicySelfTest PASS")
    }
}

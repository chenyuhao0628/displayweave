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
        let decision = SendQueuePolicy.decision(
            pendingSends: 2, budget: 2, currentDroppedFrames: 4)
        precondition(decision.shouldDrop && decision.droppedFrames == 5)
        precondition(decision.reason == .preEncodeCaptureSkip)
        precondition(!decision.forceKeyframe)
        print("SendQueuePolicySelfTest PASS")
    }
}

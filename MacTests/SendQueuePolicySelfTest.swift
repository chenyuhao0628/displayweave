import Foundation

@main
enum SendQueuePolicySelfTest {
    /// Deterministic capture/async-completion schedule, not a hardware benchmark.
    static func admittedFrames(fps: Int, latencyMs: Double, frames: Int = 600,
                               modelSynchronousReturn: Bool = false) -> Int {
        var completions: [Double] = []
        var admitted = 0
        var submissionBusyUntil = 0.0
        for frame in 0..<frames {
            let now = Double(frame) * 1_000 / Double(fps)
            completions.removeAll { $0 <= now }
            if now < submissionBusyUntil { continue }
            if !SendQueuePolicy.shouldDrop(pendingSends: 0, pendingEncodes: completions.count,
                    sendBudget: 3, encodeBudget: SendQueuePolicy.encodeBudget(fps: fps)) {
                completions.append(now + latencyMs)
                admitted += 1
                // VideoToolbox's documented contract: frame N-M must have
                // been emitted before encode(N) returns for delay limit M.
                if modelSynchronousReturn,
                   completions.count > SendQueuePolicy.frameDelayLimit(fps: fps) {
                    submissionBusyUntil = completions[completions.count - 1
                        - SendQueuePolicy.frameDelayLimit(fps: fps)]
                }
            }
            precondition(completions.count <= 2, "encoder work must remain bounded")
        }
        return admitted
    }

    static func main() {
        for fps in [40, 50] {
            precondition(admittedFrames(fps: fps, latencyMs: 28) == 600,
                         "adapted intermediate FPS must retain the asynchronous two-frame pipeline")
        }
        for latency in [19.0, 23.0, 28.0] {
            let admitted = admittedFrames(fps: 60, latencyMs: latency)
            precondition(admitted == 600,
                         "60 Hz / \(latency) ms callback: admitted \(admitted)/600 frames; avoid artificial half-rate cadence")
            let pipelined = admittedFrames(fps: 60, latencyMs: latency, modelSynchronousReturn: true)
            precondition(pipelined == 600,
                "MaxFrameDelayCount serializes capture submission: \(pipelined)/600 frames at \(latency) ms")
        }
        precondition(admittedFrames(fps: 60, latencyMs: 100) < 600,
                     "a slow encoder must still exert bounded backpressure")
        precondition(admittedFrames(fps: 60, latencyMs: 100, modelSynchronousReturn: true) < 600,
                     "allowing a pipeline must not bypass sustained encoder overload")
        precondition(SendQueuePolicy.frameDelayLimit(fps: 30) == 0)
        precondition(SendQueuePolicy.frameDelayLimit(fps: 60) == 1)
        precondition(SendQueuePolicy.frameDelayLimit(fps: 120) == 1)
        precondition(SendQueuePolicy.budget(quality: .gaming) == 1)
        precondition(SendQueuePolicy.budget(quality: .balanced) == 2)
        precondition(SendQueuePolicy.budget(quality: .high) == 3)
        precondition(SendQueuePolicy.encodeBudget(fps: 30) == 1)
        precondition(SendQueuePolicy.encodeBudget(fps: 60) == 2)
        precondition(SendQueuePolicy.encodeBudget(fps: 90) == 2)
        precondition(SendQueuePolicy.encodeBudget(fps: 120) == 2)
        precondition(!SendQueuePolicy.shouldDrop(
            pendingSends: 0, sendBudget: 1, encodeBudget: 2))
        precondition(SendQueuePolicy.shouldDrop(
            pendingSends: 1, sendBudget: 1, encodeBudget: 2))
        precondition(SendQueuePolicy.shouldDrop(
            pendingSends: 0, pendingEncodes: 2, sendBudget: 1, encodeBudget: 2))
        precondition(!SendQueuePolicy.shouldDrop(
            pendingSends: 0, pendingEncodes: 1, sendBudget: 1, encodeBudget: 2),
                     "120fps must allow a second frame while one encode is in flight")
        let decision = SendQueuePolicy.decision(
            pendingSends: 0, pendingEncodes: 2,
            sendBudget: 1, encodeBudget: 2,
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

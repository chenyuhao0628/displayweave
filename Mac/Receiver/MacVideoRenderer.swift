import AVFoundation
import CoreMedia

/// Receiver-queue interface; allows driver backpressure to be reproduced without
/// a display window or a particular hardware decoder.
protocol MacVideoRendering {
    var status: AVQueuedSampleBufferRenderingStatus { get }
    var isReadyForMoreMediaData: Bool { get }
    func enqueue(_ sample: CMSampleBuffer)
    func flush(removingDisplayedImage: Bool)
}

struct MacSampleBufferVideoRenderer: MacVideoRendering {
    let renderer: AVSampleBufferVideoRenderer
    var status: AVQueuedSampleBufferRenderingStatus { renderer.status }
    var isReadyForMoreMediaData: Bool { renderer.isReadyForMoreMediaData }
    func enqueue(_ sample: CMSampleBuffer) { renderer.enqueue(sample) }
    func flush(removingDisplayedImage: Bool) {
        if removingDisplayedImage {
            renderer.flush(removingDisplayedImage: true, completionHandler: nil)
        } else { renderer.flush() }
    }
}

/// `isReadyForMoreMediaData == false` is occupancy feedback, not a decode
/// failure. AVQueuedSampleBufferRendering permits bounded real-time enqueueing
/// in this state. Preserve short reference chains; abandon sustained backlog.
struct MacVideoBackpressurePolicy {
    enum Action { case enqueue, flushAndWait, wait }
    private var notReadySince: TimeInterval?
    private var additionalFrames = 0
    private var flushed = false

    mutating func action(isReady: Bool, now: TimeInterval) -> Action {
        if isReady {
            self = Self()
            return .enqueue
        }
        if flushed { return .wait }
        if notReadySince == nil { notReadySince = now }
        guard let notReadySince, additionalFrames < 2, now - notReadySince < 0.050 else {
            flushed = true
            return .flushAndWait
        }
        additionalFrames += 1
        return .enqueue
    }
}

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

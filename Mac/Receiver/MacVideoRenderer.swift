import AVFoundation
import CoreMedia
import Foundation

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

protocol MacAudioPlaying: AnyObject {
    var isMuted: Bool { get set }
    func enqueueS16LE(_ pcmData: Data)
    func enqueueEncodedAudio(
        formatFlags: UInt8,
        payload: Data,
        sampleRate: Int,
        channels: Int,
        captureTimestampMs: Int64,
        arrivalMonoMs: Double
    )
    func updateVideoPipelineDelay(udpJitterActive: Bool, explicitDelayMs: Double?)
    func recordVideoRender(captureTimestampMs: Int64, renderMonoMs: Double)
    func stop()
}

extension MacAudioPlaying {
    func enqueueEncodedAudio(
        formatFlags: UInt8,
        payload: Data,
        sampleRate: Int,
        channels: Int,
        captureTimestampMs: Int64,
        arrivalMonoMs: Double
    ) {
        if formatFlags == 0 {
            enqueueS16LE(payload)
        }
    }

    func updateVideoPipelineDelay(udpJitterActive: Bool, explicitDelayMs: Double?) {}
    func recordVideoRender(captureTimestampMs: Int64, renderMonoMs: Double) {}
}

final class NullMacAudioPlayer: MacAudioPlaying {
    var isMuted = false
    func enqueueS16LE(_ pcmData: Data) {}
    func stop() {}
}

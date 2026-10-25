// Snapshot reproducer: see docs/code-and-experience-audit-2026-10-26.md.
import Foundation
import CoreMedia
import VideoToolbox
enum Log { static func info(_ value: String) {} }
final class FailedEncoderProbe: @unchecked Sendable {
    let queue = DispatchQueue(label: "review.failed-encoder")
    var stopped = false
    var pipelineFailureReported = false
    var connectionReady = true
    var stream: Int? = 1
    var captureFrames = CaptureFrameReplay<Int>()
    var dropReplayWork: DispatchWorkItem?
    var dropReplayID: UUID?
    var pipelineHasCapacity = true
    var encoder: VTCompressionSession?
    var streamCodec = StreamCodec.h264
    var macCodecFallback = MacCodecFallbackPolicy()
    var activeStreamWidth = 1920
    var activeStreamHeight = 1080
    var requestedCaptureFps = 60
    var attempts = 0
    var rebuilds = 0
    var terminalFailures = 0
    func encode(_ frame: Int, pts: CMTime) {
        attempts += 1
        handleEncodeFailure(status: kVTInvalidSessionErr)
    }
    func recordEncodeFailure(_ detail: String) {}
    func setupEncoder(width: Int, height: Int, fps: Int, preferredCodec: StreamCodec) throws { rebuilds += 1 }
    func sendStreamConfig(width: Int, height: Int) {}
    func requestKeyframe(_ reason: FrameDropReason) {}
    func failPipeline(_ error: Error) { terminalFailures += 1; pipelineFailureReported = true }
    func scheduleDropReplay() {
        guard !stopped, !pipelineFailureReported, connectionReady, stream != nil else { return }
        captureFrames.dropped(at: ProcessInfo.processInfo.systemUptime)
        armDropReplay()
    }

    func armDropReplay() {
        guard let deadline = captureFrames.deadline else { return }
        dropReplayWork?.cancel()
        let id = UUID(), generation = captureFrames.generation
        dropReplayID = id
        let work = DispatchWorkItem { [weak self] in
            guard let self, !self.stopped, !self.pipelineFailureReported, self.connectionReady,
                  self.stream != nil, self.dropReplayID == id, self.captureFrames.generation == generation else { return }
            self.dropReplayWork = nil; self.dropReplayID = nil
            if let frame = self.captureFrames.takeDue(at: ProcessInfo.processInfo.systemUptime,
                                                       ready: self.pipelineHasCapacity) {
                self.encode(frame, pts: CMClockGetTime(CMClockGetHostTimeClock()))
            } else { self.armDropReplay() }
        }
        dropReplayWork = work
        queue.asyncAfter(deadline: .now() + max(0, deadline - ProcessInfo.processInfo.systemUptime), execute: work)
    }

    func handleEncodeFailure(status: OSStatus) {
        recordEncodeFailure("encode failed for \(streamCodec.label): \(status)")
        guard streamCodec == .hevc else { scheduleDropReplay(); return }
        macCodecFallback.recordFailure(.hevc)
        Log.info("falling back to H.264 after HEVC encode failure")
        if let encoder { VTCompressionSessionInvalidate(encoder) }
        encoder = nil
        do {
            try setupEncoder(width: max(activeStreamWidth, 2),
                             height: max(activeStreamHeight, 2),
                             fps: requestedCaptureFps,
                             preferredCodec: .h264)
            sendStreamConfig(width: max(activeStreamWidth, 2), height: max(activeStreamHeight, 2))
            requestKeyframe(.codecFallback)
        } catch { failPipeline(error) }
    }

}
@main struct PersistentEncoderFailureProbe {
    static func main() {
        let probe = FailedEncoderProbe()
        probe.queue.sync {
            let generation = probe.captureFrames.begin()
            probe.captureFrames.offer(1, generation: generation)
            probe.encode(1, pts: .zero)
        }
        Thread.sleep(forTimeInterval: 1.6)
        probe.queue.sync {
            print("Persistent H264 kVTInvalidSessionErr: attempts=\(probe.attempts), encoder rebuilds=\(probe.rebuilds), terminal failures=\(probe.terminalFailures), next retry armed=\(probe.dropReplayWork != nil)")
            precondition(probe.attempts > 25 && probe.rebuilds == 0 && probe.terminalFailures == 0 && probe.dropReplayWork != nil)
            probe.stopped = true
            probe.dropReplayWork?.cancel()
        }
    }
}

// Snapshot reproducer: see docs/code-and-experience-audit-2026-10-26.md.
import Foundation
import CoreMedia
enum Log { static func info(_ text: String) {} }
final class Before {

    var pendingEncodeWork = GenerationWorkCounter()
    var keyframeRequests = KeyframeRequestTracker(initialReason: .streamReconfigure)
    var connectionReady = true
    var pipelineFailureReported = false
    var wireConnectionGeneration: UInt64 = 2
    var encoderGeneration: UInt64 = 1
    var dropsThisWindow = 0
    var dropsTotal = 0
    var streamCodec = StreamCodec.h264
    func handleEncodeFailure(status: OSStatus) {}
    func recordEncodeFailure(_ detail: String) {}
    func scheduleDropReplay() {}
    static func isKeyframe(_ sample: CMSampleBuffer) -> Bool { true }
    func handleEncodedFrame(
        status: OSStatus,
        buffer: CMSampleBuffer?,
        forcedKeyframeReason: FrameDropReason?,
        capturedAtMs: Int64,
        encodedForWireGeneration: UInt64,
        encodedForEncoderGeneration: UInt64,
        encodeWorkID: GenerationWorkCounter.WorkID,
        protocolFrameIdentity: StreamProtocolFrameIdentity?,
        encodeStart: Date
    ) {
        guard pendingEncodeWork.complete(
                generation: encodedForEncoderGeneration,
                workID: encodeWorkID) else {
            Log.info("dropping duplicate/unmatched encode completion")
            return
        }
        switch EncoderCallbackPolicy.disposition(
            status: status,
            hasSampleBuffer: buffer != nil
        ) {
        case .stale: preconditionFailure("old policy has no stale disposition")
        case .failed:
            if forcedKeyframeReason != nil {
                keyframeRequests.completeInFlightRequest(encodedKeyframe: false)
            }
            handleEncodeFailure(status: status)
            return
        case .dropped:
            if forcedKeyframeReason != nil {
                keyframeRequests.completeInFlightRequest(encodedKeyframe: false)
            }
            dropsThisWindow += 1
            dropsTotal += 1
            Log.info("encoder dropped frame without output status=\(status) codec=\(streamCodec.label)")
            return
        case .output:
            break
        }
        guard let buffer else { return }
        let isKeyframe = Self.isKeyframe(buffer)
        if forcedKeyframeReason != nil {
            keyframeRequests.completeInFlightRequest(encodedKeyframe: isKeyframe)
        }
        guard connectionReady,
              encodedForWireGeneration == wireConnectionGeneration,
              encodedForEncoderGeneration == encoderGeneration else {
            Log.info("dropping encoded frame from stale wire/encoder generation")
            return
        }
    }

}
final class After {

    var pendingEncodeWork = GenerationWorkCounter()
    var keyframeRequests = KeyframeRequestTracker(initialReason: .streamReconfigure)
    var connectionReady = true
    var pipelineFailureReported = false
    var wireConnectionGeneration: UInt64 = 2
    var encoderGeneration: UInt64 = 1
    var dropsThisWindow = 0
    var dropsTotal = 0
    var streamCodec = StreamCodec.h264
    func handleEncodeFailure(status: OSStatus) {}
    func recordEncodeFailure(_ detail: String) {}
    func scheduleDropReplay() {}
    static func isKeyframe(_ sample: CMSampleBuffer) -> Bool { true }
    func handleEncodedFrame(
        status: OSStatus,
        buffer: CMSampleBuffer?,
        forcedKeyframeReason: FrameDropReason?,
        capturedAtMs: Int64,
        encodedForWireGeneration: UInt64,
        encodedForEncoderGeneration: UInt64,
        encodeWorkID: GenerationWorkCounter.WorkID,
        protocolFrameIdentity: StreamProtocolFrameIdentity?,
        encodeStart: Date
    ) {
        guard pendingEncodeWork.complete(
                generation: encodedForEncoderGeneration,
                workID: encodeWorkID) else {
            Log.info("dropping duplicate/unmatched encode completion")
            return
        }
        switch EncoderCallbackPolicy.disposition(
            status: status,
            hasSampleBuffer: buffer != nil,
            isCurrentSession: connectionReady && !pipelineFailureReported
                && encodedForWireGeneration == wireConnectionGeneration
                && encodedForEncoderGeneration == encoderGeneration
        ) {
        case .stale:
            // Errors are callbacks too: an old socket's failed encode must not
            // recreate the encoder or stop the replacement connection.
            Log.info("dropping encoded frame from stale wire/encoder generation")
            return
        case .failed:
            if forcedKeyframeReason != nil {
                keyframeRequests.completeInFlightRequest(encodedKeyframe: false)
            }
            handleEncodeFailure(status: status)
            return
        case .dropped:
            if forcedKeyframeReason != nil {
                keyframeRequests.completeInFlightRequest(encodedKeyframe: false)
            }
            dropsThisWindow += 1
            dropsTotal += 1
            recordEncodeFailure("encoder dropped frame without output status=\(status) codec=\(streamCodec.label)")
            scheduleDropReplay()
            return
        case .output:
            break
        }
        guard let buffer else { return }
        let isKeyframe = Self.isKeyframe(buffer)
        if forcedKeyframeReason != nil {
            keyframeRequests.completeInFlightRequest(encodedKeyframe: isKeyframe)
        }
    }

}

@main struct ReconnectKeyframeProbe {
    static func main() {
        var sample: CMSampleBuffer?
        let status = CMSampleBufferCreate(allocator: kCFAllocatorDefault, dataBuffer: nil,
            dataReady: true, makeDataReadyCallback: nil, refcon: nil, formatDescription: nil,
            sampleCount: 0, sampleTimingEntryCount: 0, sampleTimingArray: nil,
            sampleSizeEntryCount: 0, sampleSizeArray: nil, sampleBufferOut: &sample)
        precondition(status == noErr && sample != nil)
        let before = Before(), after = After()
        let oldBefore = before.keyframeRequests.consumePendingRequest()
        let oldAfter = after.keyframeRequests.consumePendingRequest()
        let oldBeforeWork = before.pendingEncodeWork.begin(generation: 1)
        let oldAfterWork = after.pendingEncodeWork.begin(generation: 1)
        _ = before.keyframeRequests.request(.reconnect)
        _ = after.keyframeRequests.request(.reconnect)
        before.handleEncodedFrame(status: 0, buffer: sample, forcedKeyframeReason: oldBefore,
            capturedAtMs: 0, encodedForWireGeneration: 1, encodedForEncoderGeneration: 1,
            encodeWorkID: oldBeforeWork, protocolFrameIdentity: nil, encodeStart: Date())
        after.handleEncodedFrame(status: 0, buffer: sample, forcedKeyframeReason: oldAfter,
            capturedAtMs: 0, encodedForWireGeneration: 1, encodedForEncoderGeneration: 1,
            encodeWorkID: oldAfterWork, protocolFrameIdentity: nil, encodeStart: Date())
        let nextBefore = before.keyframeRequests.consumePendingRequest()
        let nextAfter = after.keyframeRequests.consumePendingRequest()
        print("BEFORE: reconnect can force keyframe = \(nextBefore == .reconnect)")
        print("AFTER: reconnect can force keyframe = \(nextAfter == .reconnect), stale in-flight reason = \(String(describing: after.keyframeRequests.inFlightReason))")
        precondition(nextBefore == .reconnect && nextAfter == nil)
        for _ in 0..<100 {
            _ = after.keyframeRequests.request(.receiverKeyframeRequest)
            precondition(after.keyframeRequests.consumePendingRequest() == nil)
            let newWork = after.pendingEncodeWork.begin(generation: 1)
            after.handleEncodedFrame(status: 0, buffer: sample, forcedKeyframeReason: nil,
                capturedAtMs: 0, encodedForWireGeneration: 2, encodedForEncoderGeneration: 1,
                encodeWorkID: newWork, protocolFrameIdentity: nil, encodeStart: Date())
        }
        precondition(after.keyframeRequests.inFlightReason == .streamReconfigure)
        print("AFTER: 100 new-generation callbacks and keyframe requests do not clear the stale latch")
    }
}

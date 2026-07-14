import Foundation

@main
enum KeyframeRequestPolicySelfTest {
    static func main() {
        precondition(!FrameDropReason.preEncodeCaptureSkip.requiresKeyframe)
        precondition(FrameDropReason.encodedFrameDiscarded.requiresKeyframe)
        precondition(FrameDropReason.transportWriteFailure.requiresKeyframe)
        precondition(FrameDropReason.receiverKeyframeRequest.requiresKeyframe)
        precondition(FrameDropReason.decoderReset.requiresKeyframe)
        precondition(FrameDropReason.reconnect.requiresKeyframe)
        precondition(FrameDropReason.codecFallback.requiresKeyframe)
        precondition(FrameDropReason.streamReconfigure.requiresKeyframe)
        precondition(!FrameDropReason.staleSession.requiresKeyframe)

        var tracker = KeyframeRequestTracker()
        precondition(tracker.request(.preEncodeCaptureSkip) == .ignored)
        precondition(!tracker.hasPendingRequest)

        precondition(tracker.request(.reconnect) == .scheduled)
        precondition(tracker.request(.receiverKeyframeRequest) == .coalesced)
        precondition(tracker.pendingReason == .reconnect)
        precondition(tracker.requestCount == 2)
        precondition(tracker.coalescedCount == 1)

        precondition(tracker.consumePendingRequest() == .reconnect)
        precondition(!tracker.hasPendingRequest)
        precondition(tracker.inFlightReason == .reconnect)
        precondition(tracker.emittedRequestCount == 1)

        precondition(tracker.request(.receiverKeyframeRequest) == .coalesced)
        precondition(!tracker.hasPendingRequest)
        precondition(tracker.coalescedCount == 2)
        precondition(tracker.request(.streamReconfigure) == .scheduled)
        precondition(tracker.pendingReason == .streamReconfigure)
        precondition(tracker.consumePendingRequest() == nil)
        tracker.completeInFlightRequest(encodedKeyframe: true)
        precondition(tracker.inFlightReason == nil)

        precondition(tracker.consumePendingRequest() == .streamReconfigure)
        tracker.completeInFlightRequest(encodedKeyframe: true)

        precondition(tracker.request(.decoderReset) == .scheduled)
        precondition(tracker.consumePendingRequest() == .decoderReset)
        tracker.completeInFlightRequest(encodedKeyframe: true)
        precondition(tracker.emittedRequestCount == 3)
        precondition(tracker.count(for: .receiverKeyframeRequest) == 2)
        precondition(tracker.count(for: .decoderReset) == 1)

        var failedEncode = KeyframeRequestTracker()
        precondition(failedEncode.request(.codecFallback) == .scheduled)
        precondition(failedEncode.consumePendingRequest() == .codecFallback)
        failedEncode.completeInFlightRequest(encodedKeyframe: false)
        precondition(failedEncode.pendingReason == .codecFallback)
        precondition(failedEncode.consumePendingRequest() == .codecFallback)
        failedEncode.completeInFlightRequest(encodedKeyframe: true)
        precondition(!failedEncode.hasPendingRequest && failedEncode.inFlightReason == nil)

        print("KeyframeRequestPolicySelfTest PASS")
    }
}

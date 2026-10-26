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

        let reconnect = tracker.consumePendingRequest()!
        precondition(reconnect.reason == .reconnect)
        precondition(!tracker.hasPendingRequest)
        precondition(tracker.inFlightReason == .reconnect)
        precondition(tracker.emittedRequestCount == 1)

        precondition(tracker.request(.receiverKeyframeRequest) == .coalesced)
        precondition(!tracker.hasPendingRequest)
        precondition(tracker.coalescedCount == 2)
        precondition(tracker.request(.streamReconfigure) == .scheduled)
        precondition(tracker.pendingReason == .streamReconfigure)
        precondition(tracker.consumePendingRequest() == nil)
        tracker.complete(reconnect, encodedKeyframe: true)
        precondition(tracker.inFlightReason == nil)

        let reconfigure = tracker.consumePendingRequest()!
        precondition(reconfigure.reason == .streamReconfigure)
        tracker.complete(reconfigure, encodedKeyframe: true)

        precondition(tracker.request(.decoderReset) == .scheduled)
        let reset = tracker.consumePendingRequest()!
        precondition(reset.reason == .decoderReset)
        tracker.complete(reset, encodedKeyframe: true)
        precondition(tracker.emittedRequestCount == 3)
        precondition(tracker.count(for: .receiverKeyframeRequest) == 2)
        precondition(tracker.count(for: .decoderReset) == 1)

        var failedEncode = KeyframeRequestTracker()
        precondition(failedEncode.request(.codecFallback) == .scheduled)
        let failed = failedEncode.consumePendingRequest()!
        precondition(failed.reason == .codecFallback)
        failedEncode.complete(failed, encodedKeyframe: false)
        precondition(failedEncode.pendingReason == .codecFallback)
        let retried = failedEncode.consumePendingRequest()!
        precondition(retried.reason == .codecFallback)
        failedEncode.complete(retried, encodedKeyframe: true)
        precondition(!failedEncode.hasPendingRequest && failedEncode.inFlightReason == nil)

        // Replacement must work even if the retired encoder never calls back.
        var replacement = KeyframeRequestTracker(initialReason: .streamReconfigure)
        let old = replacement.consumePendingRequest()!
        _ = replacement.request(.reconnect)
        replacement.retireInFlightRequest()
        let fresh = replacement.consumePendingRequest()!
        precondition(fresh.reason == .reconnect && fresh.id != old.id)
        for _ in 0..<100 {
            replacement.complete(old, encodedKeyframe: true)
            replacement.complete(old, encodedKeyframe: false)
        }
        precondition(replacement.inFlightRequest == fresh, "stale callbacks cannot complete the replacement")
        replacement.complete(fresh, encodedKeyframe: false)
        let retry = replacement.consumePendingRequest()!
        replacement.complete(fresh, encodedKeyframe: true)
        precondition(replacement.inFlightRequest == retry, "duplicate callbacks cannot complete a retry")
        replacement.complete(retry, encodedKeyframe: true)
        precondition(!replacement.hasPendingRequest && replacement.inFlightReason == nil)
        print("KeyframeRequestPolicySelfTest PASS")
    }
}

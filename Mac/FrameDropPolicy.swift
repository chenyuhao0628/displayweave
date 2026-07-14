import Foundation

enum FrameDropReason: String, CaseIterable, Hashable {
    case preEncodeCaptureSkip
    case encodedFrameDiscarded
    case transportWriteFailure
    case receiverKeyframeRequest
    case decoderReset
    case reconnect
    case codecFallback
    case streamReconfigure
    case staleSession

    var requiresKeyframe: Bool {
        switch self {
        case .preEncodeCaptureSkip, .staleSession:
            return false
        case .encodedFrameDiscarded, .transportWriteFailure,
             .receiverKeyframeRequest, .decoderReset, .reconnect,
             .codecFallback, .streamReconfigure:
            return true
        }
    }

    var supersedesInFlightKeyframe: Bool {
        switch self {
        case .decoderReset, .reconnect, .codecFallback, .streamReconfigure:
            return true
        case .preEncodeCaptureSkip, .encodedFrameDiscarded,
             .transportWriteFailure, .receiverKeyframeRequest, .staleSession:
            return false
        }
    }
}

enum KeyframeRequestDisposition: Equatable {
    case ignored
    case scheduled
    case coalesced
}

struct KeyframeRequestTracker {
    private(set) var pendingReason: FrameDropReason?
    private(set) var inFlightReason: FrameDropReason?
    private(set) var requestCount = 0
    private(set) var coalescedCount = 0
    private(set) var emittedRequestCount = 0
    private var countsByReason: [FrameDropReason: Int] = [:]

    init(initialReason: FrameDropReason? = nil) {
        guard let initialReason, initialReason.requiresKeyframe else { return }
        pendingReason = initialReason
        requestCount = 1
        countsByReason[initialReason] = 1
    }

    var hasPendingRequest: Bool {
        pendingReason != nil
    }

    mutating func request(_ reason: FrameDropReason) -> KeyframeRequestDisposition {
        guard reason.requiresKeyframe else { return .ignored }
        requestCount += 1
        countsByReason[reason, default: 0] += 1
        guard pendingReason == nil else {
            coalescedCount += 1
            return .coalesced
        }
        if inFlightReason != nil {
            guard reason.supersedesInFlightKeyframe else {
                coalescedCount += 1
                return .coalesced
            }
            pendingReason = reason
            return .scheduled
        }
        pendingReason = reason
        return .scheduled
    }

    mutating func consumePendingRequest() -> FrameDropReason? {
        guard inFlightReason == nil, let reason = pendingReason else { return nil }
        pendingReason = nil
        inFlightReason = reason
        emittedRequestCount += 1
        return reason
    }

    mutating func completeInFlightRequest(encodedKeyframe: Bool) {
        guard let reason = inFlightReason else { return }
        inFlightReason = nil
        if !encodedKeyframe, pendingReason == nil {
            pendingReason = reason
        }
    }

    func count(for reason: FrameDropReason) -> Int {
        countsByReason[reason, default: 0]
    }
}

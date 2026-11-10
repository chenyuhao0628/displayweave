import Foundation

enum UDPBandwidthSignal: String, Sendable, Equatable {
    case normal
    case overuse
    case underuse
}

struct UDPBandwidthDecision: Equatable, Sendable {
    var previousBitrate: Int
    var newBitrate: Int
    var reason: String
    var trigger: String
    var isCongested: Bool
    var decisionEpoch: Int
    var requiresStreamConfig: Bool { false }
}

/// Receiver-side 5ms send-burst grouping and arrival-delay gradient tracker
/// that feeds `UDPMediaFeedbackPayload` packets back to the sender.
struct UDPReceiverArrivalEstimator: Sendable {
    static let burstGroupWindowUs: Int64 = 5_000
    static let maxInterBurstGapUs: Int64 = 500_000
    static let feedbackIntervalNs: UInt64 = 30_000_000 // 30 ms

    private var currentGroupStartSendUs: UInt32?
    private var currentGroupLastSendUs: UInt32 = 0
    private var currentGroupLastRecvMonoUs: Int64 = 0

    private var prevGroupSendUs: UInt32?
    private var prevGroupRecvMonoUs: Int64?

    private var smoothedGradientUs: Double = 0
    private var highestExtendedSeq: UInt64 = 0
    private var windowFirstSeq: UInt64?
    private var windowReceivedCount: UInt32 = 0
    private var latestSendTimeUs: UInt32 = 0
    private var lastFeedbackSentMonoNs: UInt64 = 0

    mutating func recordPacket(
        extendedSequence: UInt64,
        sendTimeUs: UInt32,
        arrivalMonoNs: UInt64
    ) {
        let arrivalMonoUs = Int64(arrivalMonoNs / 1_000)
        latestSendTimeUs = sendTimeUs
        if windowFirstSeq == nil {
            windowFirstSeq = extendedSequence
        }
        if extendedSequence > highestExtendedSeq {
            highestExtendedSeq = extendedSequence
        }
        windowReceivedCount &+= 1

        guard let groupStart = currentGroupStartSendUs else {
            currentGroupStartSendUs = sendTimeUs
            currentGroupLastSendUs = sendTimeUs
            currentGroupLastRecvMonoUs = arrivalMonoUs
            return
        }

        let sendDeltaFromStart = Self.unwrappedSendDeltaUs(from: groupStart, to: sendTimeUs)
        if sendDeltaFromStart < 0 {
            // Reordered packet from an older send group: do not pollute burst boundary
            return
        }
        if sendDeltaFromStart <= Self.burstGroupWindowUs {
            currentGroupLastSendUs = sendTimeUs
            currentGroupLastRecvMonoUs = arrivalMonoUs
            return
        }

        // Previous 5ms burst group completed; compute inter-group delay delta
        if let prevSend = prevGroupSendUs, let prevRecv = prevGroupRecvMonoUs {
            let dSend = Self.unwrappedSendDeltaUs(from: prevSend, to: currentGroupLastSendUs)
            let dRecv = currentGroupLastRecvMonoUs - prevRecv
            if dSend > 0 && dSend <= Self.maxInterBurstGapUs && dRecv >= 0 {
                let gradient = Double(dRecv - dSend)
                smoothedGradientUs = smoothedGradientUs * 0.75 + gradient * 0.25
            }
        }
        prevGroupSendUs = currentGroupLastSendUs
        prevGroupRecvMonoUs = currentGroupLastRecvMonoUs

        currentGroupStartSendUs = sendTimeUs
        currentGroupLastSendUs = sendTimeUs
        currentGroupLastRecvMonoUs = arrivalMonoUs
    }

    mutating func pollFeedbackIfDue(
        nowMonoNs: UInt64,
        decodeQueueMs: UInt16,
        renderFps: UInt16
    ) -> UDPMediaFeedbackPayload? {
        guard windowReceivedCount > 0 else { return nil }
        guard lastFeedbackSentMonoNs == 0
                || (nowMonoNs >= lastFeedbackSentMonoNs
                    && nowMonoNs - lastFeedbackSentMonoNs >= Self.feedbackIntervalNs) else {
            return nil
        }
        lastFeedbackSentMonoNs = nowMonoNs
        let expectedCount: UInt64
        if let first = windowFirstSeq, highestExtendedSeq >= first {
            expectedCount = (highestExtendedSeq - first) + 1
        } else {
            expectedCount = UInt64(windowReceivedCount)
        }
        let received = windowReceivedCount
        let lost = expectedCount > UInt64(received)
            ? UInt32(min(expectedCount - UInt64(received), UInt64(UInt32.max)))
            : 0
        let clampedGradient = Int32(
            max(Double(Int32.min), min(Double(Int32.max), smoothedGradientUs.rounded()))
        )
        let payload = UDPMediaFeedbackPayload(
            highestSeq: highestExtendedSeq,
            receivedCount: received,
            lostCount: lost,
            arrivalGradientUs: clampedGradient,
            decodeQueueMs: decodeQueueMs,
            renderFps: renderFps,
            echoSendTimeUs: latestSendTimeUs
        )
        windowFirstSeq = highestExtendedSeq &+ 1
        windowReceivedCount = 0
        return payload
    }

    static func unwrappedSendDeltaUs(from start: UInt32, to end: UInt32) -> Int64 {
        let diff = end &- start
        return Int64(Int32(bitPattern: diff))
    }
}

/// Sender-side 20-sample trendline delay-gradient estimator + AIMD rate controller
/// with loss safety net and encoder-load ceiling integration.
struct UDPDelayGradientBWE: Sendable {
    static let windowSize = 20
    static let minSamplesForTrendline = 5
    static let smoothingAlpha = 0.18
    static let overuseThresholdMsPerSec = 12.5
    static let betaDecrease = 0.85
    static let alphaIncreasePerSec = 1.08

    private struct TrendSample: Sendable {
        let timestamp: TimeInterval
        let smoothedDelayMs: Double
    }

    let bounds: ClosedRange<Int>
    private(set) var currentBitrate: Int
    private(set) var signal: UDPBandwidthSignal = .normal
    private(set) var latestRttMs: Double = 10.0
    private(set) var latestLossFraction: Double = 0.0
    private(set) var trendlineSlopeMsPerSec: Double = 0.0
    private(set) var decisionEpoch = 0

    private var accumulatedDelayMs: Double = 0.0
    private var smoothedDelayMs: Double = 0.0
    private var samples: [TrendSample] = []
    private var overuseCount = 0
    private var lastDecreaseAt: TimeInterval = -Double.greatestFiniteMagnitude
    private var lastUpdateAt: TimeInterval?
    private var lastEmittedBitrate: Int

    init(initialBitrate: Int, bounds: ClosedRange<Int>) {
        let clamped = min(max(initialBitrate, bounds.lowerBound), bounds.upperBound)
        self.bounds = bounds
        self.currentBitrate = clamped
        self.lastEmittedBitrate = clamped
    }

    mutating func ingestFeedback(
        _ feedback: UDPMediaFeedbackPayload,
        nowUptime: TimeInterval,
        nowSendTimeUs: UInt32
    ) -> UDPBandwidthDecision? {
        guard nowUptime.isFinite else { return nil }

        // 1. Update RTT from echoed sendTimeUs
        let rttDeltaUs = UDPReceiverArrivalEstimator.unwrappedSendDeltaUs(
            from: feedback.echoSendTimeUs,
            to: nowSendTimeUs
        )
        if rttDeltaUs > 0 && rttDeltaUs < 2_000_000 {
            let sampleRttMs = Double(rttDeltaUs) / 1_000.0
            latestRttMs = latestRttMs * 0.75 + sampleRttMs * 0.25
        }

        // 2. Update loss fraction
        let totalPackets = feedback.receivedCount &+ feedback.lostCount
        var currentWindowLoss = 0.0
        if totalPackets > 0 {
            let sampleLoss = Double(feedback.lostCount) / Double(totalPackets)
            currentWindowLoss = sampleLoss
            latestLossFraction = latestLossFraction * 0.60 + sampleLoss * 0.40
        }
        let actionableLoss = totalPackets >= 10
            ? max(currentWindowLoss, latestLossFraction)
            : latestLossFraction

        // 3. Update accumulated & EWMA-smoothed queueing delay and 20-sample trendline slope
        let deltaMs = Double(feedback.arrivalGradientUs) / 1_000.0
        accumulatedDelayMs = max(-50.0, min(500.0, accumulatedDelayMs + deltaMs))
        smoothedDelayMs = (1.0 - Self.smoothingAlpha) * smoothedDelayMs + Self.smoothingAlpha * accumulatedDelayMs

        if let lastSample = samples.last, nowUptime < lastSample.timestamp {
            samples.removeAll()
        }
        samples.append(TrendSample(timestamp: nowUptime, smoothedDelayMs: smoothedDelayMs))
        if samples.count > Self.windowSize {
            samples.removeFirst(samples.count - Self.windowSize)
        }

        trendlineSlopeMsPerSec = computeTrendlineSlope()
        if trendlineSlopeMsPerSec > Self.overuseThresholdMsPerSec {
            overuseCount += 1
            signal = overuseCount >= 2 ? .overuse : .normal
        } else if trendlineSlopeMsPerSec < -Self.overuseThresholdMsPerSec {
            overuseCount = 0
            signal = .underuse
        } else {
            overuseCount = 0
            signal = .normal
        }

        let dt = lastUpdateAt.map { max(0.0, min(1.0, nowUptime - $0)) } ?? 0.030
        lastUpdateAt = nowUptime

        // 4. AIMD + Loss & Decode Queue Safety Net
        let rttHoldSeconds = min(0.200, max(0.020, latestRttMs / 1_000.0))
        let shouldDecrease = signal == .overuse
            || actionableLoss > 0.10
            || feedback.decodeQueueMs >= 35

        if shouldDecrease {
            guard nowUptime - lastDecreaseAt >= rttHoldSeconds else {
                return nil
            }
            let previous = currentBitrate
            let decreased = Self.clamp(
                Int((Double(previous) * Self.betaDecrease).rounded()),
                to: bounds
            )
            lastDecreaseAt = nowUptime
            accumulatedDelayMs *= 0.5
            guard decreased != previous else { return nil }
            currentBitrate = decreased
            lastEmittedBitrate = decreased
            decisionEpoch += 1
            let trigger: String
            if actionableLoss > 0.10 {
                trigger = "udp-packet-loss"
            } else if signal == .overuse {
                trigger = "udp-trendline-overuse"
            } else {
                trigger = "udp-decode-queue"
            }
            return UDPBandwidthDecision(
                previousBitrate: previous,
                newBitrate: decreased,
                reason: "udpAimdDecrease",
                trigger: trigger,
                isCongested: true,
                decisionEpoch: decisionEpoch
            )
        }

        // Hold zone: underuse draining queue, pending overuse confirmation, OR moderate loss (2%..10%)
        if signal == .underuse || overuseCount > 0 || latestLossFraction >= 0.02 || feedback.decodeQueueMs > 12 {
            return nil
        }

        // Additive/Multiplicative Increase: +8%/sec when normal and loss < 2%
        guard samples.count >= Self.minSamplesForTrendline,
              dt > 0,
              nowUptime - lastDecreaseAt >= max(0.200, rttHoldSeconds * 2) else {
            return nil
        }
        let growthFactor = pow(Self.alphaIncreasePerSec, dt)
        let candidate = Self.clamp(
            Int((Double(currentBitrate) * growthFactor).rounded()),
            to: bounds
        )
        currentBitrate = candidate
        // Emit encoder update when accumulated increase reaches >= 2.5% or hits upper bound
        let relativeChange = Double(abs(currentBitrate - lastEmittedBitrate)) / Double(max(1, lastEmittedBitrate))
        guard currentBitrate > lastEmittedBitrate,
              (relativeChange >= 0.025 || currentBitrate == bounds.upperBound) else {
            return nil
        }
        let previous = lastEmittedBitrate
        lastEmittedBitrate = currentBitrate
        decisionEpoch += 1
        return UDPBandwidthDecision(
            previousBitrate: previous,
            newBitrate: currentBitrate,
            reason: "udpAimdIncrease",
            trigger: "udp-trendline-normal",
            isCongested: false,
            decisionEpoch: decisionEpoch
        )
    }

    /// Merges network BWE bitrate with optional encoder-load cap and deducts
    /// active FEC parity overhead so total emission never exceeds budget.
    func effectiveEncoderBitrate(loadCeilingBps: Int? = nil) -> Int {
        let cappedTotal = loadCeilingBps.map { min(currentBitrate, $0) } ?? currentBitrate
        return UDPMediaFECBitratePolicy.encoderBitrate(
            totalBudgetBps: cappedTotal,
            lossFraction: latestLossFraction,
            bounds: bounds
        )
    }

    private func computeTrendlineSlope() -> Double {
        guard samples.count >= Self.minSamplesForTrendline,
              let firstTime = samples.first?.timestamp else {
            return 0.0
        }
        let n = Double(samples.count)
        var sumX = 0.0
        var sumY = 0.0
        var sumXY = 0.0
        var sumXX = 0.0
        for sample in samples {
            let x = sample.timestamp - firstTime
            let y = sample.smoothedDelayMs
            sumX += x
            sumY += y
            sumXY += x * y
            sumXX += x * x
        }
        let denom = n * sumXX - sumX * sumX
        guard denom > 1e-6 else { return 0.0 }
        return (n * sumXY - sumX * sumY) / denom
    }

    private static func clamp(_ value: Int, to bounds: ClosedRange<Int>) -> Int {
        min(max(value, bounds.lowerBound), bounds.upperBound)
    }
}

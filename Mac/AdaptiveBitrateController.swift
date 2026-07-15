import Foundation

struct AdaptiveBitrateMetrics {
    var timestamp: TimeInterval
    var pendingSends: Int
    var encodedFps: Double
    var sentFps: Double
    var rttMs: Double?
    var frameAgeP95Ms: Double?
    // Per-window counts. Producers reset both after publishing each sample.
    var macDrops: Int
    var androidDrops: Int
    var androidCongestionDrops: Int
    var androidQueueDepth: Int
    var transport: BitrateTransport = .wifi
}

struct LocalCongestionMetrics {
    var timestamp: TimeInterval
    var pendingSends: Int
    var queueBudget: Int
    var oldestPendingSendAgeMs: Double
    var encodedFps: Double
    var sentFps: Double
    var sendCompletionDelayMs: Double
}

enum AdaptiveNetworkState: String {
    case stable, congested, recovering
}

struct AdaptiveBitrateDecision: Equatable {
    var previousBitrate: Int
    var newBitrate: Int
    var reason: String
    var trigger: String
    var networkState: AdaptiveNetworkState
    var decisionEpoch: Int
}

final class AdaptiveBitrateController {
    private let bounds: ClosedRange<Int>
    private let decreaseHoldSeconds: TimeInterval
    private let stableIncreaseSeconds: TimeInterval
    private let increaseCooldownSeconds: TimeInterval
    private(set) var currentBitrate: Int
    private var previousMetrics: AdaptiveBitrateMetrics?
    private var normalSince: TimeInterval?
    private var lastChangeAt = -Double.greatestFiniteMagnitude
    private var hasCongested = false
    private var consecutiveReceiverQueueWindows = 0
    private var consecutiveAndroidCongestionWindows = 0
    private var previousLocalMetrics: LocalCongestionMetrics?
    private var consecutiveLocalCongestionSamples = 0
    private(set) var decisionEpoch = 0
    private(set) var lastDecreaseReason: String?
    private(set) var lastDecreaseAt: TimeInterval?

    init(initialBitrate: Int, bounds: ClosedRange<Int>,
         decreaseHoldSeconds: TimeInterval = 1,
         stableIncreaseSeconds: TimeInterval = 5,
         increaseCooldownSeconds: TimeInterval = 5) {
        self.bounds = bounds
        self.decreaseHoldSeconds = decreaseHoldSeconds
        self.stableIncreaseSeconds = stableIncreaseSeconds
        self.increaseCooldownSeconds = increaseCooldownSeconds
        currentBitrate = Self.clamp(initialBitrate, to: bounds)
    }

    func evaluate(_ metrics: AdaptiveBitrateMetrics,
                  mode: BitrateMode) -> AdaptiveBitrateDecision? {
        guard metrics.timestamp.isFinite else {
            resetTemporalBaseline(keepLastChange: true)
            return nil
        }
        if let previousMetrics, metrics.timestamp < previousMetrics.timestamp {
            resetTemporalBaseline()
            self.previousMetrics = metrics
            return nil
        }
        guard valid(metrics) else {
            resetTemporalBaseline(keepLastChange: true)
            return nil
        }
        guard mode == .auto else {
            previousMetrics = metrics
            normalSince = nil
            consecutiveReceiverQueueWindows = 0
            consecutiveAndroidCongestionWindows = 0
            return nil
        }

        if metrics.androidQueueDepth >= 2 {
            consecutiveReceiverQueueWindows += 1
        } else {
            consecutiveReceiverQueueWindows = 0
        }
        if metrics.androidCongestionDrops > 0 {
            consecutiveAndroidCongestionWindows += 1
        } else {
            consecutiveAndroidCongestionWindows = 0
        }

        if let reason = congestionReason(metrics),
           metrics.timestamp - (lastDecreaseAt ?? -Double.greatestFiniteMagnitude)
                >= decreaseHoldSeconds {
            let previous = currentBitrate
            let decreased = Self.clamp(
                Int((Double(previous) * 0.80).rounded()), to: bounds)
            normalSince = nil
            previousMetrics = metrics
            guard decreased != previous else { return nil }
            currentBitrate = decreased
            lastChangeAt = metrics.timestamp
            hasCongested = true
            return decreaseDecision(
                previous: previous, timestamp: metrics.timestamp,
                reason: "receiverCongestionDecrease", trigger: reason)
        }

        if isNormal(metrics) {
            if normalSince == nil { normalSince = metrics.timestamp }
            if let normalSince,
               metrics.timestamp - normalSince >= stableIncreaseSeconds,
               metrics.timestamp - lastChangeAt >= increaseCooldownSeconds {
                let previous = currentBitrate
                currentBitrate = Self.clamp(
                    Int((Double(previous) * 1.07).rounded()), to: bounds)
                self.normalSince = metrics.timestamp
                lastChangeAt = metrics.timestamp
                previousMetrics = metrics
                guard currentBitrate != previous else { return nil }
                let state: AdaptiveNetworkState = hasCongested ? .recovering : .stable
                hasCongested = false
                decisionEpoch += 1
                return AdaptiveBitrateDecision(
                    previousBitrate: previous, newBitrate: currentBitrate,
                    reason: "stableRecoveryIncrease", trigger: stableReason,
                    networkState: state, decisionEpoch: decisionEpoch)
            }
        } else {
            normalSince = nil
        }
        previousMetrics = metrics
        return nil
    }

    func evaluateLocal(_ metrics: LocalCongestionMetrics,
                       mode: BitrateMode) -> AdaptiveBitrateDecision? {
        guard valid(metrics) else {
            resetLocalBaseline()
            return nil
        }
        if let previousLocalMetrics,
           metrics.timestamp < previousLocalMetrics.timestamp {
            resetLocalBaseline()
            self.previousLocalMetrics = metrics
            return nil
        }
        guard mode == .auto else {
            resetLocalBaseline()
            previousLocalMetrics = metrics
            return nil
        }

        let queueAtBudget = metrics.pendingSends >= metrics.queueBudget
        let ageRising: Bool
        if let previousLocalMetrics {
            ageRising = metrics.pendingSends > 0
                && metrics.oldestPendingSendAgeMs
                    > previousLocalMetrics.oldestPendingSendAgeMs + 1
        } else {
            ageRising = false
        }
        let congested = queueAtBudget || ageRising
        if congested {
            consecutiveLocalCongestionSamples += 1
        } else {
            consecutiveLocalCongestionSamples = 0
        }
        previousLocalMetrics = metrics

        guard consecutiveLocalCongestionSamples >= 2,
              metrics.timestamp - (lastDecreaseAt ?? -Double.greatestFiniteMagnitude)
                >= decreaseHoldSeconds else {
            return nil
        }
        let previous = currentBitrate
        let decreased = Self.clamp(
            Int((Double(previous) * 0.88).rounded()), to: bounds)
        consecutiveLocalCongestionSamples = 0
        guard decreased != previous else { return nil }
        currentBitrate = decreased
        normalSince = nil
        lastChangeAt = metrics.timestamp
        hasCongested = true
        return decreaseDecision(
            previous: previous, timestamp: metrics.timestamp,
            reason: "localFastDecrease",
            trigger: queueAtBudget
                ? "pending-budget" : "oldest-pending-age-rising")
    }

    private func congestionReason(_ metrics: AdaptiveBitrateMetrics) -> String? {
        if metrics.pendingSends >= 2 { return "pending-sends" }
        // USB capture skips usually mean VideoToolbox is busy, not that the
        // physical link is congested. Pending sends and receiver pressure are
        // still authoritative for both transports.
        if metrics.transport == .wifi && metrics.macDrops > 0 {
            return "mac-drops"
        }
        if consecutiveAndroidCongestionWindows >= 2 {
            return "android-decoder-throughput"
        }
        if consecutiveReceiverQueueWindows >= 2 { return "android-queue" }
        if metrics.transport == .wifi, metrics.encodedFps > 0,
           metrics.sentFps / metrics.encodedFps < 0.85 {
            return "send-deficit"
        }
        if metrics.transport == .wifi, let previous = previousMetrics {
            if let age = metrics.frameAgeP95Ms, let oldAge = previous.frameAgeP95Ms,
               age - oldAge > max(5, oldAge * 0.15) {
                return "frame-age-rising"
            }
            if let rtt = metrics.rttMs, let oldRTT = previous.rttMs,
               rtt - oldRTT > max(5, oldRTT * 0.50) {
                return "rtt-rising"
            }
        }
        return nil
    }

    private func isNormal(_ metrics: AdaptiveBitrateMetrics) -> Bool {
        metrics.encodedFps > 0
            && metrics.sentFps >= 0
            && metrics.pendingSends == 0
            && (metrics.transport == .usb || metrics.macDrops == 0)
            && metrics.androidCongestionDrops == 0
            && metrics.androidQueueDepth <= 1
            && metrics.sentFps / metrics.encodedFps >= 0.95
            && congestionReason(metrics) == nil
    }

    private func valid(_ metrics: AdaptiveBitrateMetrics) -> Bool {
        metrics.encodedFps.isFinite
            && metrics.sentFps.isFinite
            && metrics.encodedFps > 0
            && metrics.sentFps >= 0
            && metrics.pendingSends >= 0
            && metrics.macDrops >= 0
            && metrics.androidDrops >= 0
            && metrics.androidCongestionDrops >= 0
            && metrics.androidQueueDepth >= 0
            && (metrics.rttMs.map { $0.isFinite && $0 >= 0 } ?? true)
            && (metrics.frameAgeP95Ms.map { $0.isFinite && $0 >= 0 } ?? true)
    }

    private func valid(_ metrics: LocalCongestionMetrics) -> Bool {
        metrics.timestamp.isFinite
            && metrics.pendingSends >= 0
            && metrics.queueBudget > 0
            && metrics.oldestPendingSendAgeMs.isFinite
            && metrics.oldestPendingSendAgeMs >= 0
            && metrics.encodedFps.isFinite
            && metrics.encodedFps >= 0
            && metrics.sentFps.isFinite
            && metrics.sentFps >= 0
            && metrics.sendCompletionDelayMs.isFinite
            && metrics.sendCompletionDelayMs >= 0
    }

    private func decreaseDecision(previous: Int, timestamp: TimeInterval,
                                  reason: String, trigger: String)
        -> AdaptiveBitrateDecision {
        lastDecreaseReason = reason
        lastDecreaseAt = timestamp
        decisionEpoch += 1
        return AdaptiveBitrateDecision(
            previousBitrate: previous, newBitrate: currentBitrate,
            reason: reason, trigger: trigger, networkState: .congested,
            decisionEpoch: decisionEpoch)
    }

    private var stableReason: String {
        if stableIncreaseSeconds.rounded() == stableIncreaseSeconds {
            return "stable-\(Int(stableIncreaseSeconds))s"
        }
        return "stable-\(stableIncreaseSeconds)s"
    }

    private func resetTemporalBaseline(keepLastChange: Bool = false) {
        previousMetrics = nil
        normalSince = nil
        consecutiveReceiverQueueWindows = 0
        consecutiveAndroidCongestionWindows = 0
        if !keepLastChange { lastChangeAt = -Double.greatestFiniteMagnitude }
    }

    private func resetLocalBaseline() {
        previousLocalMetrics = nil
        consecutiveLocalCongestionSamples = 0
    }

    private static func clamp(_ value: Int, to bounds: ClosedRange<Int>) -> Int {
        min(max(value, bounds.lowerBound), bounds.upperBound)
    }
}

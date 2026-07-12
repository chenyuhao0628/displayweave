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
    var androidQueueDepth: Int
}

enum AdaptiveNetworkState: String {
    case stable, congested, recovering
}

struct AdaptiveBitrateDecision: Equatable {
    var previousBitrate: Int
    var newBitrate: Int
    var reason: String
    var networkState: AdaptiveNetworkState
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
            return nil
        }

        if metrics.androidQueueDepth >= 2 {
            consecutiveReceiverQueueWindows += 1
        } else {
            consecutiveReceiverQueueWindows = 0
        }

        if let reason = congestionReason(metrics),
           metrics.timestamp - lastChangeAt >= decreaseHoldSeconds {
            let previous = currentBitrate
            let decreased = Self.clamp(
                Int((Double(previous) * 0.80).rounded()), to: bounds)
            normalSince = nil
            previousMetrics = metrics
            guard decreased != previous else { return nil }
            currentBitrate = decreased
            lastChangeAt = metrics.timestamp
            hasCongested = true
            return AdaptiveBitrateDecision(
                previousBitrate: previous, newBitrate: currentBitrate,
                reason: reason, networkState: .congested)
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
                return AdaptiveBitrateDecision(
                    previousBitrate: previous, newBitrate: currentBitrate,
                    reason: stableReason, networkState: state)
            }
        } else {
            normalSince = nil
        }
        previousMetrics = metrics
        return nil
    }

    private func congestionReason(_ metrics: AdaptiveBitrateMetrics) -> String? {
        if metrics.pendingSends >= 2 { return "pending-sends" }
        if metrics.macDrops > 0 { return "mac-drops" }
        if metrics.androidDrops > 0 { return "android-drops" }
        if consecutiveReceiverQueueWindows >= 2 { return "android-queue" }
        if metrics.encodedFps > 0, metrics.sentFps / metrics.encodedFps < 0.85 {
            return "send-deficit"
        }
        if let previous = previousMetrics {
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
            && metrics.macDrops == 0
            && metrics.androidDrops == 0
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
            && metrics.androidQueueDepth >= 0
            && (metrics.rttMs.map { $0.isFinite && $0 >= 0 } ?? true)
            && (metrics.frameAgeP95Ms.map { $0.isFinite && $0 >= 0 } ?? true)
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
        if !keepLastChange { lastChangeAt = -Double.greatestFiniteMagnitude }
    }

    private static func clamp(_ value: Int, to bounds: ClosedRange<Int>) -> Int {
        min(max(value, bounds.lowerBound), bounds.upperBound)
    }
}

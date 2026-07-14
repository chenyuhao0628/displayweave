import Foundation

private func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() { fatalError(message) }
}

private func metrics(_ time: TimeInterval, pending: Int = 0, encoded: Double = 60,
                     sent: Double = 60, rtt: Double = 8, age: Double = 12,
                     macDrops: Int = 0, androidDrops: Int = 0,
                     androidCongestionDrops: Int = 0,
                     androidQueue: Int = 0) -> AdaptiveBitrateMetrics {
    AdaptiveBitrateMetrics(timestamp: time, pendingSends: pending, encodedFps: encoded,
        sentFps: sent, rttMs: rtt, frameAgeP95Ms: age, macDrops: macDrops,
        androidDrops: androidDrops, androidCongestionDrops: androidCongestionDrops,
        androidQueueDepth: androidQueue)
}

@main
struct AdaptiveBitrateControllerSelfTest {
    static func main() {
        let controller = AdaptiveBitrateController(
            initialBitrate: 40_000_000, bounds: 20_000_000...100_000_000)
        expect(controller.evaluate(metrics(0), mode: .auto) == nil, "normal window starts")
        expect(controller.evaluate(metrics(4.9), mode: .auto) == nil, "increase waits five seconds")
        let increase = controller.evaluate(metrics(5.0), mode: .auto)
        expect(increase?.previousBitrate == 40_000_000, "increase records previous bitrate")
        expect(increase?.newBitrate == 42_800_000, "stable window increases seven percent")
        expect(increase?.reason == "stableRecoveryIncrease"
                && increase?.trigger == "stable-5s"
                && increase?.networkState == .stable,
               "increase records reason and state")

        let decrease = controller.evaluate(metrics(6, pending: 2), mode: .auto)
        expect(decrease?.previousBitrate == 42_800_000, "decrease uses current bitrate")
        expect(decrease?.newBitrate == 34_240_000, "congestion decreases twenty percent")
        expect(decrease?.reason == "receiverCongestionDecrease"
                && decrease?.trigger == "pending-sends"
                && decrease?.networkState == .congested,
               "congestion records reason and state")
        expect(controller.evaluate(metrics(6.5, pending: 3), mode: .auto) == nil,
               "minimum hold prevents rapid repeated decreases")

        expect(controller.evaluate(metrics(7), mode: .auto) == nil, "normal period restarts")
        expect(controller.evaluate(metrics(11.9), mode: .auto) == nil, "cooldown delays increase")
        let recovered = controller.evaluate(metrics(12), mode: .auto)
        expect(recovered?.networkState == .recovering, "first increase after congestion is recovering")

        let deficit = controller.evaluate(metrics(14, encoded: 60, sent: 40), mode: .auto)
        expect(deficit?.trigger == "send-deficit", "sent/encoded deficit decreases")
        let drop = controller.evaluate(metrics(16, macDrops: 1), mode: .auto)
        expect(drop?.trigger == "mac-drops", "new Mac drops decrease")
        let receiverQueue = AdaptiveBitrateController(
            initialBitrate: 40_000_000, bounds: 20_000_000...100_000_000)
        expect(receiverQueue.evaluate(metrics(18, androidQueue: 2), mode: .auto) == nil,
               "one receiver queue spike is not sustained congestion")
        let queue = receiverQueue.evaluate(metrics(19, androidQueue: 2), mode: .auto)
        expect(queue?.trigger == "android-queue", "receiver queue decreases")
        let trends = AdaptiveBitrateController(
            initialBitrate: 80_000_000, bounds: 20_000_000...100_000_000)
        _ = trends.evaluate(metrics(20, rtt: 8, age: 12), mode: .auto)
        let risingAge = trends.evaluate(metrics(21, rtt: 8, age: 30), mode: .auto)
        expect(risingAge?.trigger == "frame-age-rising", "rising frame age decreases")
        _ = trends.evaluate(metrics(23, rtt: 8, age: 30), mode: .auto)
        let risingRTT = trends.evaluate(metrics(24, rtt: 20, age: 30), mode: .auto)
        expect(risingRTT?.trigger == "rtt-rising", "RTT jump decreases")
        expect(trends.evaluate(metrics(26, androidDrops: 1), mode: .auto) == nil,
               "unclassified Android drops do not imply congestion")
        expect(trends.evaluate(metrics(27, androidDrops: 2), mode: .auto) == nil,
               "non-congestion Android drops remain filtered")
        expect(trends.evaluate(metrics(28, androidDrops: 1,
                                       androidCongestionDrops: 1), mode: .auto) == nil,
               "one congestion-related Android drop window is not sustained")
        let androidDrop = trends.evaluate(metrics(
            29, androidDrops: 1, androidCongestionDrops: 1), mode: .auto)
        expect(androidDrop?.trigger == "android-decoder-throughput",
               "sustained congestion-related Android drops decrease")

        let filteredRecovery = AdaptiveBitrateController(
            initialBitrate: 40_000_000, bounds: 20_000_000...100_000_000)
        _ = filteredRecovery.evaluate(metrics(0, androidDrops: 3), mode: .auto)
        expect(filteredRecovery.evaluate(metrics(5, androidDrops: 2), mode: .auto)?.trigger
                == "stable-5s",
               "non-congestion Android drops do not block stable recovery")

        let floor = AdaptiveBitrateController(
            initialBitrate: 21_000_000, bounds: 20_000_000...100_000_000)
        let floorDecision = floor.evaluate(metrics(0, pending: 2), mode: .auto)
        expect(floorDecision?.newBitrate == 20_000_000, "decrease clamps to minimum")

        let ceiling = AdaptiveBitrateController(
            initialBitrate: 99_000_000, bounds: 20_000_000...100_000_000)
        _ = ceiling.evaluate(metrics(0), mode: .auto)
        expect(ceiling.evaluate(metrics(5), mode: .auto)?.newBitrate == 100_000_000,
               "increase clamps to maximum")
        let initiallyClamped = AdaptiveBitrateController(
            initialBitrate: 999_000_000, bounds: 20_000_000...100_000_000)
        expect(initiallyClamped.currentBitrate == 100_000_000, "initial bitrate clamps")

        let gray = AdaptiveBitrateController(
            initialBitrate: 40_000_000, bounds: 20_000_000...100_000_000)
        expect(gray.evaluate(metrics(0, encoded: 100, sent: 90), mode: .auto) == nil,
               "hysteresis gray zone does not decrease")
        expect(gray.evaluate(metrics(6, encoded: 100, sent: 90), mode: .auto) == nil,
               "hysteresis gray zone does not increase")

        let cooldown = AdaptiveBitrateController(
            initialBitrate: 40_000_000, bounds: 20_000_000...100_000_000,
            stableIncreaseSeconds: 2, increaseCooldownSeconds: 5)
        _ = cooldown.evaluate(metrics(0, pending: 2), mode: .auto)
        _ = cooldown.evaluate(metrics(1), mode: .auto)
        expect(cooldown.evaluate(metrics(3), mode: .auto) == nil,
               "independent cooldown blocks an otherwise stable increase")
        let cooldownDecision = cooldown.evaluate(metrics(5), mode: .auto)
        expect(cooldownDecision?.networkState == .recovering,
               "increase resumes when independent cooldown expires")
        expect(cooldownDecision?.trigger == "stable-2s", "trigger reflects configured stable window")
        expect(cooldown.evaluate(metrics(5), mode: .auto) == nil,
               "same timestamp cannot emit a duplicate decision")

        let firstTrend = AdaptiveBitrateController(
            initialBitrate: 40_000_000, bounds: 20_000_000...100_000_000)
        expect(firstTrend.evaluate(metrics(0, rtt: 200, age: 200), mode: .auto) == nil,
               "first trend sample establishes a baseline")

        let invalidTimestamp = AdaptiveBitrateController(
            initialBitrate: 80_000_000, bounds: 20_000_000...100_000_000)
        _ = invalidTimestamp.evaluate(metrics(0, pending: 2), mode: .auto)
        _ = invalidTimestamp.evaluate(metrics(.nan, pending: 2), mode: .auto)
        expect(invalidTimestamp.evaluate(metrics(0.5, pending: 2), mode: .auto) == nil,
               "nonfinite timestamp cannot bypass decrease hold")

        let unhealthy = AdaptiveBitrateController(
            initialBitrate: 40_000_000, bounds: 20_000_000...100_000_000)
        expect(unhealthy.evaluate(metrics(0, encoded: 0, sent: 0), mode: .auto) == nil,
               "zero FPS is not normal")
        expect(unhealthy.evaluate(metrics(6, encoded: 0, sent: 0), mode: .auto) == nil,
               "zero FPS never increases bitrate")
        expect(unhealthy.evaluate(metrics(7, encoded: .nan, sent: 60), mode: .auto) == nil,
               "NaN FPS is ignored")
        expect(unhealthy.evaluate(metrics(8, rtt: .infinity), mode: .auto) == nil,
               "nonfinite optional metrics are ignored")
        expect(unhealthy.evaluate(metrics(9, rtt: -1, age: -1, androidQueue: -1), mode: .auto) == nil,
               "negative latency and queue metrics are ignored")
        expect(unhealthy.evaluate(metrics(15, rtt: -1, age: -1, androidQueue: -1), mode: .auto) == nil,
               "negative metrics never form a stable increase window")

        let rollback = AdaptiveBitrateController(
            initialBitrate: 40_000_000, bounds: 20_000_000...100_000_000)
        _ = rollback.evaluate(metrics(100), mode: .auto)
        expect(rollback.evaluate(metrics(10), mode: .auto) == nil,
               "timestamp rollback resets the temporal baseline")
        _ = rollback.evaluate(metrics(11), mode: .auto)
        expect(rollback.evaluate(metrics(16), mode: .auto) != nil,
               "controller recovers after a new monotonic epoch")

        let fixed = AdaptiveBitrateController(
            initialBitrate: 40_000_000, bounds: 20_000_000...100_000_000)
        expect(fixed.evaluate(metrics(0, pending: 3), mode: .manual) == nil,
               "Manual never adapts")
        expect(fixed.evaluate(metrics(1, pending: 3), mode: .benchmark) == nil,
               "Benchmark never adapts")

        let local = AdaptiveBitrateController(
            initialBitrate: 40_000_000, bounds: 20_000_000...100_000_000)
        let fullQueue = LocalCongestionMetrics(
            timestamp: 0, pendingSends: 2, queueBudget: 2,
            oldestPendingSendAgeMs: 20, encodedFps: 60, sentFps: 50,
            sendCompletionDelayMs: 18)
        expect(local.evaluateLocal(fullQueue, mode: .auto) == nil,
               "one local queue sample is not enough")
        var secondQueue = fullQueue
        secondQueue.timestamp = 0.2
        let fast = local.evaluateLocal(secondQueue, mode: .auto)
        expect(fast?.newBitrate == 35_200_000,
               "local fast path decreases twelve percent")
        expect(fast?.reason == "localFastDecrease"
                && fast?.trigger == "pending-budget",
               "local decision records source and trigger")
        expect(fast?.decisionEpoch == 1, "first decision starts epoch one")
        expect(local.lastDecreaseReason == "localFastDecrease",
               "shared state records the local decrease reason")
        expect(local.lastDecreaseAt == 0.2,
               "shared state records the local decrease time")
        expect(local.evaluate(metrics(0.4, pending: 2), mode: .auto) == nil,
               "receiver loop cannot double-decrease inside the shared hold")
        expect(local.currentBitrate == 35_200_000,
               "blocked receiver decrease leaves local result unchanged")

        let receiverFirst = AdaptiveBitrateController(
            initialBitrate: 40_000_000, bounds: 20_000_000...100_000_000)
        let receiverFirstDecision = receiverFirst.evaluate(
            metrics(0, pending: 2), mode: .auto)
        expect(receiverFirstDecision?.reason == "receiverCongestionDecrease",
               "receiver path records its unified source")
        _ = receiverFirst.evaluateLocal(fullQueue, mode: .auto)
        expect(receiverFirst.evaluateLocal(secondQueue, mode: .auto) == nil,
               "local path cannot double-decrease inside a receiver hold")
        expect(receiverFirst.currentBitrate == 32_000_000,
               "blocked local decrease leaves receiver result unchanged")

        let growingAge = AdaptiveBitrateController(
            initialBitrate: 50_000_000, bounds: 20_000_000...100_000_000)
        func localAge(_ time: Double, _ age: Double) -> LocalCongestionMetrics {
            LocalCongestionMetrics(
                timestamp: time, pendingSends: 1, queueBudget: 2,
                oldestPendingSendAgeMs: age, encodedFps: 60, sentFps: 55,
                sendCompletionDelayMs: age)
        }
        expect(growingAge.evaluateLocal(localAge(0, 10), mode: .auto) == nil,
               "first age sample establishes a baseline")
        expect(growingAge.evaluateLocal(localAge(0.2, 20), mode: .auto) == nil,
               "one rising-age sample is not enough")
        let ageDecision = growingAge.evaluateLocal(localAge(0.4, 30), mode: .auto)
        expect(ageDecision?.trigger == "oldest-pending-age-rising",
               "two rising-age samples trigger local decrease")
        let afterLocal = growingAge.currentBitrate
        for index in 1...20 {
            _ = growingAge.evaluateLocal(localAge(0.4 + Double(index) * 0.2, 0),
                                         mode: .auto)
        }
        expect(growingAge.currentBitrate == afterLocal,
               "local fast path never increases bitrate")

        let localDisabled = AdaptiveBitrateController(
            initialBitrate: 40_000_000, bounds: 20_000_000...100_000_000)
        _ = localDisabled.evaluateLocal(fullQueue, mode: .manual)
        expect(localDisabled.evaluateLocal(secondQueue, mode: .manual) == nil,
               "local fast path is disabled outside Auto")
        print("AdaptiveBitrateControllerSelfTest PASS")
    }
}

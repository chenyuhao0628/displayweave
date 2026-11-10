import Foundation

private func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() { fatalError(message) }
}

@main
struct UDPDelayGradientBWESelfTest {
    static func main() {
        // 1. Receiver 5ms burst grouping and arrival gradient estimation
        var receiverEst = UDPReceiverArrivalEstimator()
        // Burst 1 at sendTime 10_000 us, recv 10_000_000 ns
        receiverEst.recordPacket(extendedSequence: 1, sendTimeUs: 10_000, arrivalMonoNs: 10_000_000)
        receiverEst.recordPacket(extendedSequence: 2, sendTimeUs: 11_000, arrivalMonoNs: 11_000_000)
        // Burst 2 at sendTime 26_000 us (+15ms send delta), but arrives at 30_000_000 ns (+19ms recv delta -> +4000us gradient)
        receiverEst.recordPacket(extendedSequence: 4, sendTimeUs: 26_000, arrivalMonoNs: 30_000_000)
        // Burst 3 triggers completion of Burst 2
        receiverEst.recordPacket(extendedSequence: 5, sendTimeUs: 42_000, arrivalMonoNs: 50_000_000)

        let fb = receiverEst.pollFeedbackIfDue(nowMonoNs: 50_000_000, decodeQueueMs: 3, renderFps: 60)
        expect(fb != nil, "feedback is emitted after 30ms window")
        expect(fb?.highestSeq == 5 && fb?.receivedCount == 4 && fb?.lostCount == 1,
               "sequence gap (missing seq 3) is reported as 1 lost packet out of 5")
        expect((fb?.arrivalGradientUs ?? 0) > 0,
               "rising queueing delay produces positive arrivalGradientUs")

        // 2. Sender 20-sample trendline overuse detection + AIMD 0.85x decrease
        var bwe = UDPDelayGradientBWE(
            initialBitrate: 40_000_000,
            bounds: 10_000_000...100_000_000
        )
        var decision: UDPBandwidthDecision?
        for i in 1...8 {
            let overuseFb = UDPMediaFeedbackPayload(
                highestSeq: UInt64(i * 10),
                receivedCount: 10,
                lostCount: 0,
                arrivalGradientUs: 4_500, // +4.5ms queueing delay per 30ms report
                decodeQueueMs: 5,
                renderFps: 60,
                echoSendTimeUs: UInt32(i * 30_000 - 12_000)
            )
            if let d = bwe.ingestFeedback(
                overuseFb,
                nowUptime: Double(i) * 0.035,
                nowSendTimeUs: UInt32(i * 30_000)
            ) {
                decision = d
                break
            }
        }
        expect(decision != nil, "sustained positive delay gradient triggers overuse decrease")
        expect(decision?.newBitrate == 34_000_000 && decision?.trigger == "udp-trendline-overuse",
               "AIMD multiplicative decrease cuts 40 Mbps by 0.85x to 34 Mbps")
        expect(decision?.requiresStreamConfig == false,
               "BWE decision never triggers streamConfig")

        // 3. Loss safety net (>10% loss triggers decrease even with flat delay gradient)
        let lossFb = UDPMediaFeedbackPayload(
            highestSeq: 200,
            receivedCount: 80,
            lostCount: 20, // 20% loss
            arrivalGradientUs: 0,
            decodeQueueMs: 2,
            renderFps: 60,
            echoSendTimeUs: 500_000
        )
        let lossDecision = bwe.ingestFeedback(lossFb, nowUptime: 1.0, nowSendTimeUs: 515_000)
        expect(lossDecision?.trigger == "udp-packet-loss" && lossDecision?.newBitrate == 28_900_000,
               ">10% packet loss triggers 0.85x decrease")

        // 4. Normal recovery (+8%/sec when delay gradient is ~0 and loss < 2%)
        var recoveredDecision: UDPBandwidthDecision?
        for step in 1...25 {
            let t = 1.0 + Double(step) * 0.10
            let normalFb = UDPMediaFeedbackPayload(
                highestSeq: UInt64(200 + step * 20),
                receivedCount: 20,
                lostCount: 0,
                arrivalGradientUs: -200,
                decodeQueueMs: 2,
                renderFps: 60,
                echoSendTimeUs: UInt32(step * 100_000)
            )
            if let d = bwe.ingestFeedback(normalFb, nowUptime: t, nowSendTimeUs: UInt32(step * 100_000 + 8_000)) {
                recoveredDecision = d
            }
        }
        expect(recoveredDecision != nil && bwe.currentBitrate > 28_900_000,
               "healthy delay gradient and <2% loss smoothly recovers bitrate upward")

        // 5. Effective encoder bitrate merges encoder-load cap and FEC deduction
        let effective = bwe.effectiveEncoderBitrate(loadCeilingBps: 25_000_000)
        expect(effective <= 25_000_000, "effective encoder bitrate respects loadCeilingBps and deducts FEC overhead")

        print("UDPDelayGradientBWESelfTest PASS")
    }
}

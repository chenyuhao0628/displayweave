import Foundation

private func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() { fatalError(message) }
}

@main
struct BenchmarkIntegrationPolicySelfTest {
    static func main() throws {
        let statsData = Data(#"{"type":"stats","receivedFps":117.5,"actualBitrateMbps":42.25,"androidQueueDepth":2}"#.utf8)
        let decoded = try BenchmarkControlPolicy.receiverStats(from: statsData)
        expect(decoded?.receivedFps == 117.5, "stats controls decode as ReceiverStats")
        expect(decoded?.actualBitrateMbps == 42.25, "receiver wire bitrate remains distinct")
        let nonStats = try BenchmarkControlPolicy.receiverStats(
            from: Data(#"{"type":"hello"}"#.utf8))
        expect(nonStats == nil,
               "non-stats controls are ignored")

        let pong = try BenchmarkControlPolicy.pongData(
            pingTimestamp: 1000, macReceivedTimestamp: 1010, macSentTimestamp: 1011)
        let object = try JSONSerialization.jsonObject(with: pong) as! [String: Any]
        expect(object["type"] as? String == "pong", "pong type")
        expect(object["t"] as? Double == 1000, "pong echoes Android timestamp")
        expect(object["mt"] as? Double == 1011, "legacy mt remains the Mac send timestamp")
        expect(object["mr"] as? Double == 1010, "pong includes Mac receive timestamp")
        expect(object["ms"] as? Double == 1011, "pong includes Mac send timestamp")

        expect(!BenchmarkRecordingGate.shouldAppend(isRecorderActive: false, hasReceiverStats: true),
               "inactive recorder never appends")
        expect(BenchmarkRecordingGate.shouldAppend(isRecorderActive: true, hasReceiverStats: true),
               "active recorder appends receiver samples")
        expect(!BenchmarkRecordingGate.shouldAppend(isRecorderActive: true, hasReceiverStats: false),
               "a sample requires receiver stats")

        let policy = BenchmarkPhasePolicy(warmupSeconds: 30, runSeconds: 180)
        expect(policy.phase(elapsedSeconds: 0) == .warmup, "starts in warmup")
        expect(policy.phase(elapsedSeconds: 29.999) == .warmup, "warmup lasts 30 seconds")
        expect(policy.phase(elapsedSeconds: 30) == .run, "run follows warmup")
        expect(policy.phase(elapsedSeconds: 210) == .finished, "finishes after selected duration")
        print("BenchmarkIntegrationPolicySelfTest PASS")
    }
}

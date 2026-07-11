import Foundation

private func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

@main
struct BenchmarkSampleSelfTest {
static func main() throws {
let statsJSON = """
{
  "type": "stats",
  "receivedFps": 58.5,
  "decodedFps": 57.5,
  "renderedFps": 56.5,
  "sendToRenderEstimatedMs": 31.25,
  "rttMs": 4.5,
  "clockOffsetMs": -1.25,
  "offsetConfidenceMs": 0.75,
  "clockState": "stable",
  "frameAgeAvgMs": 20.0,
  "frameAgeLatestMs": 22.0,
  "frameAgeP50Ms": 19.0,
  "frameAgeP95Ms": 29.0,
  "frameAgeP99Ms": 35.0,
  "estimatedE2ELatencyMs": 33.0,
  "androidQueueDepth": 2,
  "androidDroppedFrames": 3,
  "inputP50Ms": 7.0,
  "inputP95Ms": null
}
"""

let stats = try JSONDecoder().decode(ReceiverStats.self, from: Data(statsJSON.utf8))
expect(stats.type == "stats", "receiver stats type")
expect(stats.sendToRenderEstimatedMs == 31.25, "canonical send-to-render metric decodes")
expect(stats.inputP95Ms == nil, "explicit JSON null remains nil")

let sample = BenchmarkSample(
    timestamp: Date(timeIntervalSince1970: 1_700_000_000.125),
    monotonicElapsedMs: 1234.5,
    runId: "run,\"one\"",
    sessionId: "session\nline",
    scene: "desktop",
    phase: "steady",
    deviceModel: "Pixel 9",
    transport: "adb-usb",
    codec: "hevc",
    resolution: .init(width: 1920, height: 1080),
    requestedFps: 60,
    actualVirtualDisplayRefreshRate: 59.94,
    captureFps: 60,
    encodedFps: 59,
    sentFps: 58,
    receiver: stats,
    targetBitrateMbps: 20,
    encodeLatencyMs: 4.25,
    pendingSends: 1,
    macQueue: 2,
    macDrops: 0,
    macCPU: 22.5,
    macMemory: nil
)

let csv = sample.csv(includeHeader: true)
let headerCount = BenchmarkSample.csvHeader.count
expect(sample.csvFields.count == headerCount, "fixed header count equals row count")
expect(csv.contains("\"run,\"\"one\"\"\""), "CSV escapes comma and quotes")
expect(csv.contains("\"session\nline\""), "CSV escapes newline")
expect(sample.csvFields.contains(BenchmarkSample.notAvailable), "nil writes notAvailable in CSV")
expect(BenchmarkSample.csvHeader.first == "timestamp", "fixed header starts with timestamp")
expect(BenchmarkSample.csvHeader.last == "macMemory", "fixed header ends with macMemory")

let jsonLine = try sample.jsonLine()
let jsonObject = try JSONSerialization.jsonObject(with: Data(jsonLine.utf8)) as! [String: Any]
expect(jsonObject["macMemory"] is NSNull, "nil writes JSON null")
expect(jsonObject["sendToRenderEstimatedMs"] as? Double == 31.25, "JSONL uses canonical send-to-render field")
expect((jsonObject["resolution"] as? [String: Any])?["width"] as? Int == 1920, "JSONL contains resolution")
expect((jsonObject["timestamp"] as? String)?.hasSuffix("Z") == true, "wall timestamp is ISO8601")
expect(jsonObject["monotonicElapsedMs"] as? Double == 1234.5, "monotonic elapsed is caller supplied")

print("BenchmarkSampleSelfTest passed")
}
}

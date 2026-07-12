import Foundation

private func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

private func parseCSV(_ text: String) -> [[String]] {
    var rows: [[String]] = []
    var row: [String] = []
    var field = ""
    var quoted = false
    let characters = Array(text)
    var index = 0
    while index < characters.count {
        let character = characters[index]
        if character == "\"" {
            if quoted, index + 1 < characters.count, characters[index + 1] == "\"" {
                field.append("\"")
                index += 1
            } else {
                quoted.toggle()
            }
        } else if character == ",", !quoted {
            row.append(field)
            field = ""
        } else if character == "\r\n", !quoted {
            row.append(field)
            rows.append(row)
            row = []
            field = ""
        } else if character == "\r", !quoted,
                  index + 1 < characters.count, characters[index + 1] == "\n" {
            row.append(field)
            rows.append(row)
            row = []
            field = ""
            index += 1
        } else {
            field.append(character)
        }
        index += 1
    }
    row.append(field)
    rows.append(row)
    return rows
}

@main
struct BenchmarkSampleSelfTest {
static func main() throws {
let statsJSON = """
{
  "type": "stats",
  "timestamp": 1234,
  "deviceModel": "Pixel 9",
  "transport": "usb",
  "codec": "hevc",
  "width": 1920,
  "height": 1080,
  "requestedFps": 60,
  "actualAndroidDisplayRefreshRate": 59.94,
  "receivedFps": 58.5,
  "decodedFps": 57.5,
  "renderedFps": 56.5,
  "sendToRenderEstimatedMs": 31.25,
  "rttMs": 4.5,
  "clockOffsetMs": -1.25,
  "offsetConfidenceMs": 0.75,
  "clockRttMs": null,
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
expect(stats.deviceModel == "Pixel 9" && stats.width == 1920, "canonical identity fields decode")
expect(stats.frameAgeP99Ms == 35 && stats.androidQueueDepth == 2, "canonical metric fields decode")
expect(stats.clockRttMs == nil, "canonical nullable clock field remains nil")
expect(stats.sendToRenderEstimatedMs == 31.25, "canonical send-to-render metric decodes")
expect(stats.inputP95Ms == nil, "explicit JSON null remains nil")

let sample = BenchmarkSample(
    timestamp: Date(timeIntervalSince1970: 1_700_000_000.125),
    monotonicElapsed: .seconds(1.2345),
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
    actualBitrateMbps: 18.25,
    previousBitrateMbps: 24,
    newBitrateMbps: 20,
    bitrateChangeReason: "pending-sends",
    networkState: "congested",
    keyframeCount: 2,
    averageKeyframeSize: 125_000,
    peakFrameSize: 140_000,
    keyframeQueueDepth: 1,
    keyframeFrameAgeP95Ms: 30,
    decoderRecoveryEvent: "receiver-kf",
    averageFrameSize: 41_234.5,
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
let parsedCSV = parseCSV(csv)
expect(parsedCSV.count == 2, "RFC 4180 parser sees header and one data record, got \(parsedCSV.count)")
expect(parsedCSV[0].count == headerCount && parsedCSV[1].count == headerCount,
       "parsed RFC 4180 rows have stable column counts")
expect(csv.contains("\"run,\"\"one\"\"\""), "CSV escapes comma and quotes")
expect(csv.contains("\"session\nline\""), "CSV escapes newline")
expect(sample.csvFields.contains(BenchmarkSample.notAvailable), "nil writes notAvailable in CSV")
expect(BenchmarkSample.csvHeader.first == "timestamp", "fixed header starts with timestamp")
expect(BenchmarkSample.csvHeader.last == "decoderRecoveryEvent", "fixed header ends with recovery event")
var nonFiniteSample = sample
nonFiniteSample.macCPU = Double.infinity
expect(nonFiniteSample.csvFields[BenchmarkSample.csvHeader.firstIndex(of: "macCPU")!] == BenchmarkSample.notAvailable,
       "nonfinite CSV values write notAvailable")
nonFiniteSample.actualBitrateMbps = -Double.infinity
nonFiniteSample.requestedFps = Double.nan
let nonFiniteJSON = try nonFiniteSample.jsonLine()
let nonFiniteObject = try JSONSerialization.jsonObject(with: Data(nonFiniteJSON.utf8)) as! [String: Any]
expect(nonFiniteObject["macCPU"] is NSNull, "positive infinity writes JSON null")
expect(nonFiniteObject["actualBitrateMbps"] is NSNull, "negative infinity writes JSON null")
expect(nonFiniteObject["requestedFps"] is NSNull, "required NaN writes JSON null")

let jsonLine = try sample.jsonLine()
let jsonObject = try JSONSerialization.jsonObject(with: Data(jsonLine.utf8)) as! [String: Any]
expect(jsonObject["macMemory"] is NSNull, "nil writes JSON null")
expect(jsonObject["sendToRenderEstimatedMs"] as? Double == 31.25, "JSONL uses canonical send-to-render field")
expect(jsonObject["targetBitrateMbps"] as? Double == 20, "target bitrate stays configured")
expect(jsonObject["actualBitrateMbps"] as? Double == 18.25, "actual bitrate stays measured")
expect(jsonObject["previousBitrateMbps"] as? Double == 24, "previous adaptive target is recorded")
expect(jsonObject["newBitrateMbps"] as? Double == 20, "new adaptive target is recorded")
expect(jsonObject["bitrateChangeReason"] as? String == "pending-sends", "adaptive reason is recorded")
expect(jsonObject["networkState"] as? String == "congested", "adaptive state is recorded")
expect(jsonObject["keyframeCount"] as? Double == 2, "keyframe count is recorded")
expect(jsonObject["decoderRecoveryEvent"] as? String == "receiver-kf", "recovery event is recorded")
expect(jsonObject["averageFrameSize"] as? Double == 41_234.5, "local frame size stays measured")
expect((jsonObject["resolution"] as? [String: Any])?["width"] as? Int == 1920, "JSONL contains resolution")
expect((jsonObject["timestamp"] as? String)?.hasSuffix("Z") == true, "wall timestamp is ISO8601")
expect(jsonObject["monotonicElapsedMs"] as? Double == 1234.5, "monotonic elapsed is caller supplied")

print("BenchmarkSampleSelfTest passed")
}
}

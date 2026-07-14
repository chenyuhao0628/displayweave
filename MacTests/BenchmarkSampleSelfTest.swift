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
  "requestedSurfaceFrameRate": 60.0,
  "actualAndroidDisplayRefreshRate": 59.94,
  "frameRateApplyResult": "applied:streamConfig:window=60Hz,surface=onlyIfSeamless",
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
  "inputP95Ms": null,
  "currentFrameBytes": 420000,
  "maxFrameBytesObserved": 8100000,
  "currentKeyframeBytes": 7600000,
  "maxKeyframeBytesObserved": 8100000,
  "oversizeFrameCount": 2,
  "invalidFrameLengthCount": 3,
  "decoderName": "c2.vendor.hevc.decoder",
  "hardwareAccelerated": true,
  "softwareOnly": false,
  "vendor": true,
  "lowLatencySupported": true,
  "lowLatencyEnabled": true,
  "decoderConfigureSuccess": true,
  "decoderFallbackReason": "",
  "decoderLowLatencyMode": "auto",
  "wifiLowLatencyMode": "auto",
  "wifiLowLatencyRequested": true,
  "wifiLowLatencyAcquired": true,
  "wifiLowLatencyActive": true,
  "wifiLowLatencyReleaseReason": "",
  "androidDropCountsWindow": {"decoderInputUnavailable": 2, "surfaceUnavailable": 1},
  "androidDropCountsTotal": {"decoderInputUnavailable": 7, "surfaceUnavailable": 3},
  "androidCongestionDrops": 2,
  "androidDropTotal": 10,
  "androidLastDrop": {
    "reason": "decoderInputUnavailable",
    "countWindow": 2,
    "countTotal": 7,
    "generation": 3,
    "sessionEpoch": 8,
    "configVersion": 12,
    "frameSequence": 44,
    "codec": "hevc",
    "transport": "wifi"
  }
}
"""

let stats = try JSONDecoder().decode(ReceiverStats.self, from: Data(statsJSON.utf8))
expect(stats.type == "stats", "receiver stats type")
expect(stats.deviceModel == "Pixel 9" && stats.width == 1920, "canonical identity fields decode")
expect(stats.frameAgeP99Ms == 35 && stats.androidQueueDepth == 2, "canonical metric fields decode")
expect(stats.clockRttMs == nil, "canonical nullable clock field remains nil")
expect(stats.sendToRenderEstimatedMs == 31.25, "canonical send-to-render metric decodes")
expect(stats.inputP95Ms == nil, "explicit JSON null remains nil")
expect(stats.maxFrameBytesObserved == 8_100_000, "maximum frame size metric decodes")
expect(stats.oversizeFrameCount == 2 && stats.invalidFrameLengthCount == 3,
       "frame-length rejection counters decode")
expect(stats.decoderName == "c2.vendor.hevc.decoder" && stats.hardwareAccelerated == true,
       "actual decoder identity and acceleration decode")
expect(stats.lowLatencySupported == true && stats.lowLatencyEnabled == true,
       "decoder low-latency state decodes")
expect(stats.decoderLowLatencyMode == "auto", "requested low-latency mode decodes")
expect(stats.requestedSurfaceFrameRate == 60,
       "requested Surface frame rate decodes separately")
expect(stats.frameRateApplyResult?.contains("onlyIfSeamless") == true,
       "Surface apply result decodes")
expect(stats.wifiLowLatencyRequested == true && stats.wifiLowLatencyActive == true,
       "WiFi low-latency lifecycle state decodes")
expect(stats.androidDropCountsWindow?["decoderInputUnavailable"] == 2,
       "Android drop reason window counts decode")
expect(stats.androidCongestionDrops == 2,
       "congestion-relevant Android drop count decodes")
expect(stats.androidLastDrop?.frameSequence == 44,
       "last Android drop context decodes")

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
    bitrateChangeReason: "localFastDecrease",
    bitrateChangeTrigger: "pending-budget",
    decisionEpoch: 3,
    lastDecreaseReason: "localFastDecrease",
    lastDecreaseAt: 1_700_000_000.2,
    localOldestPendingSendAgeMs: 32,
    localSendCompletionDelayMs: 18,
    localEncodedFps: 60,
    localSentFps: 50,
    networkState: "congested",
    keyframeCount: 2,
    averageKeyframeSize: 125_000,
    peakFrameSize: 140_000,
    keyframeQueueDepth: 1,
    keyframeFrameAgeP95Ms: 30,
    keyframeRequestReason: "reconnect",
    keyframeRequestCount: 4,
    keyframeCoalescedCount: 2,
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
expect(Set(BenchmarkSample.csvHeader).count == headerCount,
       "fixed header contains no duplicate column names")
let parsedCSV = parseCSV(csv)
expect(parsedCSV.count == 2, "RFC 4180 parser sees header and one data record, got \(parsedCSV.count)")
expect(parsedCSV[0].count == headerCount && parsedCSV[1].count == headerCount,
       "parsed RFC 4180 rows have stable column counts")
expect(csv.contains("\"run,\"\"one\"\"\""), "CSV escapes comma and quotes")
expect(csv.contains("\"session\nline\""), "CSV escapes newline")
expect(sample.csvFields.contains(BenchmarkSample.notAvailable), "nil writes notAvailable in CSV")
expect(BenchmarkSample.csvHeader.first == "timestamp", "fixed header starts with timestamp")
expect(BenchmarkSample.csvHeader.contains("keyframeRequestReason"), "header records keyframe request reason")
expect(BenchmarkSample.csvHeader.contains("keyframeRequestCount"), "header records keyframe request count")
expect(BenchmarkSample.csvHeader.contains("keyframeCoalescedCount"), "header records coalesced requests")
expect(BenchmarkSample.csvHeader.contains("maxFrameBytesObserved"), "header records maximum frame size")
expect(BenchmarkSample.csvHeader.contains("invalidFrameLengthCount"), "header records invalid lengths")
expect(BenchmarkSample.csvHeader.contains("decoderName"), "header records actual decoder")
expect(BenchmarkSample.csvHeader.contains("lowLatencyEnabled"), "header records low-latency state")
expect(BenchmarkSample.csvHeader.contains("requestedSurfaceFrameRate"),
       "header records requested Surface frame rate")
expect(BenchmarkSample.csvHeader.contains("wifiLowLatencyActive"),
       "header records WiFi low-latency active state")
expect(BenchmarkSample.csvHeader.contains("androidDropCountsWindow"),
       "header records Android drop reasons")
expect(BenchmarkSample.csvHeader.contains("androidLastDropFrameSequence"),
       "header records Android drop identity context")
expect(BenchmarkSample.csvHeader.contains("bitrateChangeTrigger"),
       "header records fast-decrease trigger")
expect(BenchmarkSample.csvHeader.contains("decisionEpoch"),
       "header records unified decision identity")
expect(BenchmarkSample.csvHeader.contains("localOldestPendingSendAgeMs"),
       "header records local queue age")
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
expect(jsonObject["bitrateChangeReason"] as? String == "localFastDecrease",
       "adaptive decision source is recorded")
expect(jsonObject["networkState"] as? String == "congested", "adaptive state is recorded")
expect(jsonObject["keyframeCount"] as? Double == 2, "keyframe count is recorded")
expect(jsonObject["keyframeRequestReason"] as? String == "reconnect", "keyframe request reason is recorded")
expect(jsonObject["keyframeRequestCount"] as? Double == 4, "keyframe request count is recorded")
expect(jsonObject["keyframeCoalescedCount"] as? Double == 2, "coalesced keyframe count is recorded")
expect(jsonObject["decoderRecoveryEvent"] as? String == "receiver-kf", "recovery event is recorded")
expect(jsonObject["averageFrameSize"] as? Double == 41_234.5, "local frame size stays measured")
expect(jsonObject["currentFrameBytes"] as? Double == 420_000, "current frame bytes are recorded")
expect(jsonObject["maxFrameBytesObserved"] as? Double == 8_100_000, "maximum frame bytes are recorded")
expect(jsonObject["currentKeyframeBytes"] as? Double == 7_600_000, "current keyframe bytes are recorded")
expect(jsonObject["maxKeyframeBytesObserved"] as? Double == 8_100_000, "maximum keyframe bytes are recorded")
expect(jsonObject["oversizeFrameCount"] as? Double == 2, "oversize frame count is recorded")
expect(jsonObject["invalidFrameLengthCount"] as? Double == 3, "invalid frame length count is recorded")
expect(jsonObject["decoderName"] as? String == "c2.vendor.hevc.decoder", "decoder name is recorded")
expect(jsonObject["hardwareAccelerated"] as? Bool == true, "hardware acceleration is recorded")
expect(jsonObject["softwareOnly"] as? Bool == false, "software-only state is recorded")
expect(jsonObject["decoderVendor"] as? Bool == true, "decoder vendor state is recorded")
expect(jsonObject["lowLatencySupported"] as? Bool == true, "low-latency support is recorded")
expect(jsonObject["lowLatencyEnabled"] as? Bool == true, "low-latency enablement is recorded")
expect(jsonObject["decoderConfigureSuccess"] as? Bool == true, "decoder configure success is recorded")
expect(jsonObject["decoderFallbackReason"] as? String == "", "decoder fallback reason is recorded")
expect(jsonObject["decoderLowLatencyMode"] as? String == "auto", "requested decoder mode is recorded")
expect(jsonObject["requestedSurfaceFrameRate"] as? Double == 60,
       "requested Surface frame rate is recorded")
expect((jsonObject["frameRateApplyResult"] as? String)?.contains("onlyIfSeamless") == true,
       "Surface frame-rate apply result is recorded")
expect(jsonObject["wifiLowLatencyMode"] as? String == "auto",
       "WiFi low-latency mode is recorded")
expect(jsonObject["wifiLowLatencyRequested"] as? Bool == true,
       "WiFi low-latency request is recorded")
expect(jsonObject["wifiLowLatencyAcquired"] as? Bool == true,
       "WiFi low-latency ownership is recorded")
expect(jsonObject["wifiLowLatencyActive"] as? Bool == true,
       "WiFi low-latency lifecycle activity is recorded")
expect(jsonObject["wifiLowLatencyReleaseReason"] as? String == "",
       "WiFi low-latency release reason is recorded")
expect((jsonObject["androidDropCountsWindow"] as? [String: Double])?["decoderInputUnavailable"] == 2,
       "Android drop reason counts are recorded")
expect(jsonObject["androidCongestionDrops"] as? Double == 2,
       "congestion-relevant Android drops are recorded")
expect(jsonObject["androidLastDropFrameSequence"] as? Double == 44,
       "Android last-drop identity is recorded")
expect(jsonObject["bitrateChangeTrigger"] as? String == "pending-budget",
       "local fast-decrease trigger is recorded")
expect(jsonObject["decisionEpoch"] as? Double == 3,
       "decision epoch is recorded")
expect(jsonObject["localOldestPendingSendAgeMs"] as? Double == 32,
       "oldest pending-send age is recorded")
expect((jsonObject["resolution"] as? [String: Any])?["width"] as? Int == 1920, "JSONL contains resolution")
expect((jsonObject["timestamp"] as? String)?.hasSuffix("Z") == true, "wall timestamp is ISO8601")
expect(jsonObject["monotonicElapsedMs"] as? Double == 1234.5, "monotonic elapsed is caller supplied")

print("BenchmarkSampleSelfTest passed")
}
}

import Foundation

struct ReceiverStats: Decodable {
    var type: String
    var timestamp: Double?
    var deviceModel: String?
    var transport: String?
    var codec: String?
    var width: Int?
    var height: Int?
    var requestedFps: Double?
    var actualAndroidDisplayRefreshRate: Double?
    var receivedFps: Double?
    var decodedFps: Double?
    var renderedFps: Double?
    var rttMs: Double?
    var clockOffsetMs: Double?
    var offsetConfidenceMs: Double?
    var clockRttMs: Double?
    var clockState: String?
    var frameAgeAvgMs: Double?
    var frameAgeLatestMs: Double?
    var frameAgeP50Ms: Double?
    var frameAgeP95Ms: Double?
    var frameAgeP99Ms: Double?
    var estimatedE2ELatencyMs: Double?
    var sendToRenderEstimatedMs: Double?
    var androidQueueDepth: Double?
    var androidDroppedFrames: Double?
    var inputP50Ms: Double?
    var inputP95Ms: Double?

    // Forward-compatible fields that may be supplied by a newer receiver.
    var actualBitrateMbps: Double?
    var averageFrameSize: Double?
}

struct BenchmarkResolution: Codable {
    var width: Int
    var height: Int
}

struct BenchmarkSample {
    static let notAvailable = "notAvailable"

    var timestamp: Date
    var monotonicElapsedMs: Double
    var runId: String
    var sessionId: String
    var scene: String
    var phase: String
    var deviceModel: String
    var transport: String
    var codec: String
    var resolution: BenchmarkResolution
    var requestedFps: Double
    var actualVirtualDisplayRefreshRate: Double?
    var actualAndroidDisplayRefreshRate: Double?
    var captureFps: Double?
    var encodedFps: Double?
    var sentFps: Double?
    var receivedFps: Double?
    var decodedFps: Double?
    var renderedFps: Double?
    var targetBitrateMbps: Double?
    var actualBitrateMbps: Double?
    var averageFrameSize: Double?
    var encodeLatencyMs: Double?
    var sendToRenderEstimatedMs: Double?
    var rttMs: Double?
    var clockOffsetMs: Double?
    var offsetConfidenceMs: Double?
    var clockState: String?
    var frameAgeAvgMs: Double?
    var frameAgeLatestMs: Double?
    var frameAgeP50Ms: Double?
    var frameAgeP95Ms: Double?
    var frameAgeP99Ms: Double?
    var estimatedE2ELatencyMs: Double?
    var pendingSends: Double?
    var macQueue: Double?
    var androidQueue: Double?
    var macDrops: Double?
    var androidDrops: Double?
    var inputP50Ms: Double?
    var inputP95Ms: Double?
    var macCPU: Double?
    var macMemory: Double?

    init(timestamp: Date, monotonicElapsedMs: Double, runId: String, sessionId: String,
         scene: String, phase: String, deviceModel: String, transport: String,
         codec: String, resolution: BenchmarkResolution, requestedFps: Double,
         actualVirtualDisplayRefreshRate: Double?, captureFps: Double?, encodedFps: Double?,
         sentFps: Double?, receiver: ReceiverStats, targetBitrateMbps: Double?,
         encodeLatencyMs: Double?, pendingSends: Double?, macQueue: Double?,
         macDrops: Double?, macCPU: Double?, macMemory: Double?) {
        self.timestamp = timestamp
        self.monotonicElapsedMs = monotonicElapsedMs
        self.runId = runId
        self.sessionId = sessionId
        self.scene = scene
        self.phase = phase
        self.deviceModel = deviceModel
        self.transport = transport
        self.codec = codec
        self.resolution = resolution
        self.requestedFps = requestedFps
        self.actualVirtualDisplayRefreshRate = actualVirtualDisplayRefreshRate
        actualAndroidDisplayRefreshRate = receiver.actualAndroidDisplayRefreshRate
        self.captureFps = captureFps
        self.encodedFps = encodedFps
        self.sentFps = sentFps
        receivedFps = receiver.receivedFps
        decodedFps = receiver.decodedFps
        renderedFps = receiver.renderedFps
        self.targetBitrateMbps = targetBitrateMbps
        actualBitrateMbps = receiver.actualBitrateMbps
        averageFrameSize = receiver.averageFrameSize
        self.encodeLatencyMs = encodeLatencyMs
        sendToRenderEstimatedMs = receiver.sendToRenderEstimatedMs
        rttMs = receiver.rttMs
        clockOffsetMs = receiver.clockOffsetMs
        offsetConfidenceMs = receiver.offsetConfidenceMs
        clockState = receiver.clockState
        frameAgeAvgMs = receiver.frameAgeAvgMs
        frameAgeLatestMs = receiver.frameAgeLatestMs
        frameAgeP50Ms = receiver.frameAgeP50Ms
        frameAgeP95Ms = receiver.frameAgeP95Ms
        frameAgeP99Ms = receiver.frameAgeP99Ms
        estimatedE2ELatencyMs = receiver.estimatedE2ELatencyMs
        self.pendingSends = pendingSends
        self.macQueue = macQueue
        androidQueue = receiver.androidQueueDepth
        self.macDrops = macDrops
        androidDrops = receiver.androidDroppedFrames
        inputP50Ms = receiver.inputP50Ms
        inputP95Ms = receiver.inputP95Ms
        self.macCPU = macCPU
        self.macMemory = macMemory
    }

    static let csvHeader = [
        "timestamp", "monotonicElapsedMs", "runId", "sessionId", "scene", "phase",
        "deviceModel", "transport", "codec", "width", "height", "requestedFps",
        "actualVirtualDisplayRefreshRate", "actualAndroidDisplayRefreshRate", "captureFps",
        "encodedFps", "sentFps", "receivedFps", "decodedFps", "renderedFps",
        "targetBitrateMbps", "actualBitrateMbps", "averageFrameSize", "encodeLatencyMs",
        "sendToRenderEstimatedMs", "rttMs", "clockOffsetMs", "offsetConfidenceMs",
        "clockState", "frameAgeAvgMs", "frameAgeLatestMs", "frameAgeP50Ms",
        "frameAgeP95Ms", "frameAgeP99Ms", "estimatedE2ELatencyMs", "pendingSends",
        "macQueue", "androidQueue", "macDrops", "androidDrops", "inputP50Ms", "inputP95Ms",
        "macCPU", "macMemory"
    ]

    var csvFields: [String] {
        [isoTimestamp, number(monotonicElapsedMs), runId, sessionId, scene, phase,
         deviceModel, transport, codec, String(resolution.width), String(resolution.height),
         number(requestedFps), number(actualVirtualDisplayRefreshRate),
         number(actualAndroidDisplayRefreshRate), number(captureFps), number(encodedFps),
         number(sentFps), number(receivedFps), number(decodedFps), number(renderedFps),
         number(targetBitrateMbps), number(actualBitrateMbps), number(averageFrameSize),
         number(encodeLatencyMs), number(sendToRenderEstimatedMs), number(rttMs),
         number(clockOffsetMs), number(offsetConfidenceMs), clockState ?? Self.notAvailable,
         number(frameAgeAvgMs), number(frameAgeLatestMs), number(frameAgeP50Ms),
         number(frameAgeP95Ms), number(frameAgeP99Ms), number(estimatedE2ELatencyMs),
         number(pendingSends), number(macQueue), number(androidQueue), number(macDrops),
         number(androidDrops), number(inputP50Ms), number(inputP95Ms), number(macCPU),
         number(macMemory)]
    }

    func csv(includeHeader: Bool) -> String {
        let row = csvFields.map(Self.escapeCSV).joined(separator: ",")
        guard includeHeader else { return row }
        return Self.csvHeader.map(Self.escapeCSV).joined(separator: ",") + "\n" + row
    }

    func jsonLine() throws -> String {
        var object: [String: Any] = [
            "timestamp": isoTimestamp,
            "monotonicElapsedMs": monotonicElapsedMs,
            "runId": runId,
            "sessionId": sessionId,
            "scene": scene,
            "phase": phase,
            "deviceModel": deviceModel,
            "transport": transport,
            "codec": codec,
            "resolution": ["width": resolution.width, "height": resolution.height],
            "requestedFps": requestedFps
        ]
        let optional: [String: Any?] = [
            "actualVirtualDisplayRefreshRate": actualVirtualDisplayRefreshRate,
            "actualAndroidDisplayRefreshRate": actualAndroidDisplayRefreshRate,
            "captureFps": captureFps, "encodedFps": encodedFps, "sentFps": sentFps,
            "receivedFps": receivedFps, "decodedFps": decodedFps, "renderedFps": renderedFps,
            "targetBitrateMbps": targetBitrateMbps, "actualBitrateMbps": actualBitrateMbps,
            "averageFrameSize": averageFrameSize, "encodeLatencyMs": encodeLatencyMs,
            "sendToRenderEstimatedMs": sendToRenderEstimatedMs, "rttMs": rttMs,
            "clockOffsetMs": clockOffsetMs, "offsetConfidenceMs": offsetConfidenceMs,
            "clockState": clockState, "frameAgeAvgMs": frameAgeAvgMs,
            "frameAgeLatestMs": frameAgeLatestMs, "frameAgeP50Ms": frameAgeP50Ms,
            "frameAgeP95Ms": frameAgeP95Ms, "frameAgeP99Ms": frameAgeP99Ms,
            "estimatedE2ELatencyMs": estimatedE2ELatencyMs, "pendingSends": pendingSends,
            "macQueue": macQueue, "androidQueue": androidQueue, "macDrops": macDrops,
            "androidDrops": androidDrops, "inputP50Ms": inputP50Ms, "inputP95Ms": inputP95Ms,
            "macCPU": macCPU, "macMemory": macMemory
        ]
        for (key, value) in optional { object[key] = value ?? NSNull() }
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        return String(decoding: data, as: UTF8.self)
    }

    private var isoTimestamp: String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: timestamp)
    }

    private func number(_ value: Double?) -> String {
        guard let value, value.isFinite else { return Self.notAvailable }
        return String(format: "%.3f", value)
    }

    private static func escapeCSV(_ value: String) -> String {
        guard value.contains(",") || value.contains("\"") || value.contains("\n") || value.contains("\r")
        else { return value }
        return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}

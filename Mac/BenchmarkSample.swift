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
    var requestedSurfaceFrameRate: Double?
    var actualAndroidDisplayRefreshRate: Double?
    var frameRateApplyResult: String?
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
    var currentFrameBytes: Double?
    var maxFrameBytesObserved: Double?
    var currentKeyframeBytes: Double?
    var maxKeyframeBytesObserved: Double?
    var oversizeFrameCount: Double?
    var invalidFrameLengthCount: Double?
    var decoderName: String?
    var hardwareAccelerated: Bool?
    var softwareOnly: Bool?
    var vendor: Bool?
    var lowLatencySupported: Bool?
    var lowLatencyEnabled: Bool?
    var decoderConfigureSuccess: Bool?
    var decoderFallbackReason: String?
    var decoderLowLatencyMode: String?
    var wifiLowLatencyMode: String?
    var wifiLowLatencyRequested: Bool?
    var wifiLowLatencyAcquired: Bool?
    var wifiLowLatencyActive: Bool?
    var wifiLowLatencyReleaseReason: String?

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
    var monotonicElapsed: ContinuousClock.Duration
    var monotonicElapsedMs: Double {
        let parts = monotonicElapsed.components
        return Double(parts.seconds) * 1_000 + Double(parts.attoseconds) / 1_000_000_000_000_000
    }
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
    var requestedSurfaceFrameRate: Double?
    var actualAndroidDisplayRefreshRate: Double?
    var frameRateApplyResult: String?
    var captureFps: Double?
    var encodedFps: Double?
    var sentFps: Double?
    var receivedFps: Double?
    var decodedFps: Double?
    var renderedFps: Double?
    var targetBitrateMbps: Double?
    var actualBitrateMbps: Double?
    var averageFrameSize: Double?
    var currentFrameBytes: Double?
    var maxFrameBytesObserved: Double?
    var currentKeyframeBytes: Double?
    var maxKeyframeBytesObserved: Double?
    var oversizeFrameCount: Double?
    var invalidFrameLengthCount: Double?
    var decoderName: String?
    var hardwareAccelerated: Bool?
    var softwareOnly: Bool?
    var decoderVendor: Bool?
    var lowLatencySupported: Bool?
    var lowLatencyEnabled: Bool?
    var decoderConfigureSuccess: Bool?
    var decoderFallbackReason: String?
    var decoderLowLatencyMode: String?
    var wifiLowLatencyMode: String?
    var wifiLowLatencyRequested: Bool?
    var wifiLowLatencyAcquired: Bool?
    var wifiLowLatencyActive: Bool?
    var wifiLowLatencyReleaseReason: String?
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
    var previousBitrateMbps: Double?
    var newBitrateMbps: Double?
    var bitrateChangeReason: String?
    var networkState: String?
    var keyframeCount: Double?
    var averageKeyframeSize: Double?
    var peakFrameSize: Double?
    var keyframeQueueDepth: Double?
    var keyframeFrameAgeP95Ms: Double?
    var keyframeRequestReason: String?
    var keyframeRequestCount: Double?
    var keyframeCoalescedCount: Double?
    var decoderRecoveryEvent: String?

    init(timestamp: Date, monotonicElapsed: ContinuousClock.Duration,
         runId: String, sessionId: String,
         scene: String, phase: String, deviceModel: String, transport: String,
         codec: String, resolution: BenchmarkResolution, requestedFps: Double,
         actualVirtualDisplayRefreshRate: Double?, captureFps: Double?, encodedFps: Double?,
         sentFps: Double?, receiver: ReceiverStats, targetBitrateMbps: Double?,
         actualBitrateMbps: Double? = nil,
         previousBitrateMbps: Double? = nil, newBitrateMbps: Double? = nil,
         bitrateChangeReason: String? = nil, networkState: String? = nil,
         keyframeCount: Double? = nil, averageKeyframeSize: Double? = nil,
         peakFrameSize: Double? = nil, keyframeQueueDepth: Double? = nil,
         keyframeFrameAgeP95Ms: Double? = nil,
         keyframeRequestReason: String? = nil,
         keyframeRequestCount: Double? = nil,
         keyframeCoalescedCount: Double? = nil,
         decoderRecoveryEvent: String? = nil,
         averageFrameSize localAverageFrameSize: Double? = nil,
         encodeLatencyMs: Double?,
         pendingSends: Double?, macQueue: Double?,
         macDrops: Double?, macCPU: Double?, macMemory: Double?) {
        self.timestamp = timestamp
        self.monotonicElapsed = monotonicElapsed
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
        requestedSurfaceFrameRate = receiver.requestedSurfaceFrameRate
        actualAndroidDisplayRefreshRate = receiver.actualAndroidDisplayRefreshRate
        frameRateApplyResult = receiver.frameRateApplyResult
        self.captureFps = captureFps
        self.encodedFps = encodedFps
        self.sentFps = sentFps
        receivedFps = receiver.receivedFps
        decodedFps = receiver.decodedFps
        renderedFps = receiver.renderedFps
        self.targetBitrateMbps = targetBitrateMbps
        self.actualBitrateMbps = actualBitrateMbps ?? receiver.actualBitrateMbps
        self.previousBitrateMbps = previousBitrateMbps
        self.newBitrateMbps = newBitrateMbps
        self.bitrateChangeReason = bitrateChangeReason
        self.networkState = networkState
        self.keyframeCount = keyframeCount
        self.averageKeyframeSize = averageKeyframeSize
        self.peakFrameSize = peakFrameSize
        self.keyframeQueueDepth = keyframeQueueDepth
        self.keyframeFrameAgeP95Ms = keyframeFrameAgeP95Ms
        self.keyframeRequestReason = keyframeRequestReason
        self.keyframeRequestCount = keyframeRequestCount
        self.keyframeCoalescedCount = keyframeCoalescedCount
        self.decoderRecoveryEvent = decoderRecoveryEvent
        averageFrameSize = localAverageFrameSize ?? receiver.averageFrameSize
        currentFrameBytes = receiver.currentFrameBytes
        maxFrameBytesObserved = receiver.maxFrameBytesObserved
        currentKeyframeBytes = receiver.currentKeyframeBytes
        maxKeyframeBytesObserved = receiver.maxKeyframeBytesObserved
        oversizeFrameCount = receiver.oversizeFrameCount
        invalidFrameLengthCount = receiver.invalidFrameLengthCount
        decoderName = receiver.decoderName
        hardwareAccelerated = receiver.hardwareAccelerated
        softwareOnly = receiver.softwareOnly
        decoderVendor = receiver.vendor
        lowLatencySupported = receiver.lowLatencySupported
        lowLatencyEnabled = receiver.lowLatencyEnabled
        decoderConfigureSuccess = receiver.decoderConfigureSuccess
        decoderFallbackReason = receiver.decoderFallbackReason
        decoderLowLatencyMode = receiver.decoderLowLatencyMode
        wifiLowLatencyMode = receiver.wifiLowLatencyMode
        wifiLowLatencyRequested = receiver.wifiLowLatencyRequested
        wifiLowLatencyAcquired = receiver.wifiLowLatencyAcquired
        wifiLowLatencyActive = receiver.wifiLowLatencyActive
        wifiLowLatencyReleaseReason = receiver.wifiLowLatencyReleaseReason
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
        "actualVirtualDisplayRefreshRate", "requestedSurfaceFrameRate",
        "actualAndroidDisplayRefreshRate", "frameRateApplyResult", "captureFps",
        "encodedFps", "sentFps", "receivedFps", "decodedFps", "renderedFps",
        "targetBitrateMbps", "actualBitrateMbps", "averageFrameSize",
        "currentFrameBytes", "maxFrameBytesObserved", "currentKeyframeBytes",
        "maxKeyframeBytesObserved", "oversizeFrameCount", "invalidFrameLengthCount",
        "decoderName", "hardwareAccelerated", "softwareOnly", "decoderVendor",
        "lowLatencySupported", "lowLatencyEnabled", "decoderConfigureSuccess",
        "decoderFallbackReason", "decoderLowLatencyMode",
        "wifiLowLatencyMode", "wifiLowLatencyRequested", "wifiLowLatencyAcquired",
        "wifiLowLatencyActive", "wifiLowLatencyReleaseReason",
        "encodeLatencyMs",
        "sendToRenderEstimatedMs", "rttMs", "clockOffsetMs", "offsetConfidenceMs",
        "clockState", "frameAgeAvgMs", "frameAgeLatestMs", "frameAgeP50Ms",
        "frameAgeP95Ms", "frameAgeP99Ms", "estimatedE2ELatencyMs", "pendingSends",
        "macQueue", "androidQueue", "macDrops", "androidDrops", "inputP50Ms", "inputP95Ms",
        "macCPU", "macMemory", "previousBitrateMbps", "newBitrateMbps",
        "bitrateChangeReason", "networkState", "keyframeCount", "averageKeyframeSize",
        "peakFrameSize", "keyframeQueueDepth", "keyframeFrameAgeP95Ms",
        "keyframeRequestReason", "keyframeRequestCount", "keyframeCoalescedCount",
        "decoderRecoveryEvent"
    ]

    var csvFields: [String] {
        [isoTimestamp, number(monotonicElapsedMs), runId, sessionId, scene, phase,
         deviceModel, transport, codec, String(resolution.width), String(resolution.height),
         number(requestedFps), number(actualVirtualDisplayRefreshRate),
         number(requestedSurfaceFrameRate), number(actualAndroidDisplayRefreshRate),
         frameRateApplyResult ?? Self.notAvailable,
         number(captureFps), number(encodedFps),
         number(sentFps), number(receivedFps), number(decodedFps), number(renderedFps),
         number(targetBitrateMbps), number(actualBitrateMbps), number(averageFrameSize),
         number(currentFrameBytes), number(maxFrameBytesObserved),
         number(currentKeyframeBytes), number(maxKeyframeBytesObserved),
         number(oversizeFrameCount), number(invalidFrameLengthCount),
         decoderName ?? Self.notAvailable, boolean(hardwareAccelerated),
         boolean(softwareOnly), boolean(decoderVendor),
         boolean(lowLatencySupported), boolean(lowLatencyEnabled),
         boolean(decoderConfigureSuccess),
         decoderFallbackReason ?? Self.notAvailable,
         decoderLowLatencyMode ?? Self.notAvailable,
         wifiLowLatencyMode ?? Self.notAvailable,
         boolean(wifiLowLatencyRequested), boolean(wifiLowLatencyAcquired),
         boolean(wifiLowLatencyActive),
         wifiLowLatencyReleaseReason ?? Self.notAvailable,
         number(encodeLatencyMs), number(sendToRenderEstimatedMs), number(rttMs),
         number(clockOffsetMs), number(offsetConfidenceMs), clockState ?? Self.notAvailable,
         number(frameAgeAvgMs), number(frameAgeLatestMs), number(frameAgeP50Ms),
         number(frameAgeP95Ms), number(frameAgeP99Ms), number(estimatedE2ELatencyMs),
         number(pendingSends), number(macQueue), number(androidQueue), number(macDrops),
         number(androidDrops), number(inputP50Ms), number(inputP95Ms), number(macCPU),
         number(macMemory), number(previousBitrateMbps), number(newBitrateMbps),
         bitrateChangeReason ?? Self.notAvailable, networkState ?? Self.notAvailable,
         number(keyframeCount), number(averageKeyframeSize), number(peakFrameSize),
         number(keyframeQueueDepth), number(keyframeFrameAgeP95Ms),
         keyframeRequestReason ?? Self.notAvailable, number(keyframeRequestCount),
         number(keyframeCoalescedCount),
         decoderRecoveryEvent ?? Self.notAvailable]
    }

    func csv(includeHeader: Bool) -> String {
        let row = csvFields.map(Self.escapeCSV).joined(separator: ",")
        guard includeHeader else { return row }
        return Self.csvHeader.map(Self.escapeCSV).joined(separator: ",") + "\r\n" + row
    }

    func jsonLine() throws -> String {
        var object: [String: Any] = [
            "timestamp": isoTimestamp,
            "monotonicElapsedMs": Self.jsonNumber(monotonicElapsedMs),
            "runId": runId,
            "sessionId": sessionId,
            "scene": scene,
            "phase": phase,
            "deviceModel": deviceModel,
            "transport": transport,
            "codec": codec,
            "resolution": ["width": resolution.width, "height": resolution.height],
            "requestedFps": Self.jsonNumber(requestedFps)
        ]
        let optional: [String: Any?] = [
            "actualVirtualDisplayRefreshRate": actualVirtualDisplayRefreshRate,
            "requestedSurfaceFrameRate": requestedSurfaceFrameRate,
            "actualAndroidDisplayRefreshRate": actualAndroidDisplayRefreshRate,
            "frameRateApplyResult": frameRateApplyResult,
            "captureFps": captureFps, "encodedFps": encodedFps, "sentFps": sentFps,
            "receivedFps": receivedFps, "decodedFps": decodedFps, "renderedFps": renderedFps,
            "targetBitrateMbps": targetBitrateMbps, "actualBitrateMbps": actualBitrateMbps,
            "averageFrameSize": averageFrameSize,
            "currentFrameBytes": currentFrameBytes,
            "maxFrameBytesObserved": maxFrameBytesObserved,
            "currentKeyframeBytes": currentKeyframeBytes,
            "maxKeyframeBytesObserved": maxKeyframeBytesObserved,
            "oversizeFrameCount": oversizeFrameCount,
            "invalidFrameLengthCount": invalidFrameLengthCount,
            "decoderName": decoderName,
            "hardwareAccelerated": hardwareAccelerated,
            "softwareOnly": softwareOnly,
            "decoderVendor": decoderVendor,
            "lowLatencySupported": lowLatencySupported,
            "lowLatencyEnabled": lowLatencyEnabled,
            "decoderConfigureSuccess": decoderConfigureSuccess,
            "decoderFallbackReason": decoderFallbackReason,
            "decoderLowLatencyMode": decoderLowLatencyMode,
            "wifiLowLatencyMode": wifiLowLatencyMode,
            "wifiLowLatencyRequested": wifiLowLatencyRequested,
            "wifiLowLatencyAcquired": wifiLowLatencyAcquired,
            "wifiLowLatencyActive": wifiLowLatencyActive,
            "wifiLowLatencyReleaseReason": wifiLowLatencyReleaseReason,
            "encodeLatencyMs": encodeLatencyMs,
            "sendToRenderEstimatedMs": sendToRenderEstimatedMs, "rttMs": rttMs,
            "clockOffsetMs": clockOffsetMs, "offsetConfidenceMs": offsetConfidenceMs,
            "clockState": clockState, "frameAgeAvgMs": frameAgeAvgMs,
            "frameAgeLatestMs": frameAgeLatestMs, "frameAgeP50Ms": frameAgeP50Ms,
            "frameAgeP95Ms": frameAgeP95Ms, "frameAgeP99Ms": frameAgeP99Ms,
            "estimatedE2ELatencyMs": estimatedE2ELatencyMs, "pendingSends": pendingSends,
            "macQueue": macQueue, "androidQueue": androidQueue, "macDrops": macDrops,
            "androidDrops": androidDrops, "inputP50Ms": inputP50Ms, "inputP95Ms": inputP95Ms,
            "macCPU": macCPU, "macMemory": macMemory,
            "previousBitrateMbps": previousBitrateMbps, "newBitrateMbps": newBitrateMbps,
            "bitrateChangeReason": bitrateChangeReason, "networkState": networkState,
            "keyframeCount": keyframeCount, "averageKeyframeSize": averageKeyframeSize,
            "peakFrameSize": peakFrameSize, "keyframeQueueDepth": keyframeQueueDepth,
            "keyframeFrameAgeP95Ms": keyframeFrameAgeP95Ms,
            "keyframeRequestReason": keyframeRequestReason,
            "keyframeRequestCount": keyframeRequestCount,
            "keyframeCoalescedCount": keyframeCoalescedCount,
            "decoderRecoveryEvent": decoderRecoveryEvent
        ]
        for (key, value) in optional {
            if let number = value as? Double {
                object[key] = Self.jsonNumber(number)
            } else {
                object[key] = value ?? NSNull()
            }
        }
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

    private func boolean(_ value: Bool?) -> String {
        guard let value else { return Self.notAvailable }
        return value ? "true" : "false"
    }

    private static func escapeCSV(_ value: String) -> String {
        guard value.contains(",") || value.contains("\"") || value.contains("\n") || value.contains("\r")
        else { return value }
        return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    private static func jsonNumber(_ value: Double) -> Any {
        value.isFinite ? value : NSNull()
    }
}

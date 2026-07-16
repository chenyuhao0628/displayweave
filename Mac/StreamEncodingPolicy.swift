import Foundation

enum StreamCodec: String {
    case hevc
    case h264

    var label: String {
        switch self {
        case .hevc: return "HEVC"
        case .h264: return "H.264"
        }
    }
}

enum BitrateTransport {
    case wifi, usb
}

enum EncoderCallbackDisposition: Equatable {
    case output
    case dropped
    case failed
}

enum EncoderCallbackPolicy {
    static func disposition(status: Int32, hasSampleBuffer: Bool) -> EncoderCallbackDisposition {
        guard status == 0 else { return .failed }
        return hasSampleBuffer ? .output : .dropped
    }
}

enum StreamEncodingPolicy {
    static func bitrateBounds(codec: StreamCodec,
                              transport: BitrateTransport) -> ClosedRange<Int> {
        switch (codec, transport) {
        case (.hevc, .wifi): return 12_000_000...100_000_000
        case (.hevc, .usb): return 20_000_000...160_000_000
        case (.h264, .wifi): return 8_000_000...60_000_000
        case (.h264, .usb): return 10_000_000...100_000_000
        }
    }

    static func selectedBitrate(mode: BitrateMode, preset: BitratePreset,
                                automatic: Int, codec: StreamCodec,
                                transport: BitrateTransport) -> Int {
        if mode == .benchmark {
            return min(max(preset.bitsPerSecond, 1_000_000), 200_000_000)
        }
        let bounds = bitrateBounds(codec: codec, transport: transport)
        let requested = mode == .manual ? preset.bitsPerSecond : automatic
        return min(max(requested, bounds.lowerBound), bounds.upperBound)
    }

    static func availablePresets(mode: BitrateMode, codec: StreamCodec,
                                 transport: BitrateTransport) -> [BitratePreset] {
        guard mode != .auto else { return [] }
        if mode == .benchmark { return BitratePreset.benchmarkCases }
        let bounds = bitrateBounds(codec: codec, transport: transport)
        return BitratePreset.manualCases.filter { bounds.contains($0.bitsPerSecond) }
    }

    static func selectedCodec(supportedCodecs: [String], preferredCodec: String?) -> StreamCodec {
        let normalized = Set(supportedCodecs.map { $0.lowercased() })
        if let preferredCodec = preferredCodec?.lowercased(),
           let preferred = StreamCodec(rawValue: preferredCodec),
           normalized.contains(preferred.rawValue) {
            return preferred
        }
        if normalized.contains(StreamCodec.hevc.rawValue) {
            return .hevc
        }
        return .h264
    }

    static func bitrate(width: Int, height: Int, fps: Int, codec: StreamCodec,
                        quality: StreamQuality = .high,
                        transport: BitrateTransport = .wifi) -> Int {
        let sanitizedFps = RefreshRatePolicy.sanitize(fps)
        let megapixels = max(1.0, Double(width * height) / 1_000_000.0)
        let mbps: Double
        switch codec {
        case .hevc:
            mbps = megapixels * Double(sanitizedFps) * 0.12
        case .h264:
            mbps = megapixels * Double(sanitizedFps) * 0.10
        }
        let transportMultiplier: Double
        switch (codec, transport) {
        case (_, .wifi): transportMultiplier = 1.0
        case (.hevc, .usb): transportMultiplier = 1.35
        case (.h264, .usb): transportMultiplier = 1.25
        }
        let requested = Int((mbps * quality.bitrateMultiplier
            * transportMultiplier * 1_000_000).rounded())
        let bounds = bitrateBounds(codec: codec, transport: transport)
        return min(max(requested, bounds.lowerBound), bounds.upperBound)
    }

    static func keyframeInterval(fps: Int) -> Int {
        RefreshRatePolicy.sanitize(fps)
    }

    static func frameDurationTimescale(fps: Int) -> Int {
        RefreshRatePolicy.sanitize(fps)
    }
}

struct StreamDebugStats {
    var droppedFramesMac: Int
    var queueDepthMac: Int
    var pendingEncodesMac: Int
    var totalPendingWorkMac: Int
    var pendingEncodePeak: Int
    var captureFps: Int
    var requestedFps: Int
    var actualVirtualDisplayRefreshRate: Int
    var encodedFps: Int
    var sentFps: Int
    var averageFrameSize: Int
    var encodeLatencyMs: Double
    var bitrate: Int
    var inputP50Ms: Double
    var inputP95Ms: Double

    func pingJson(nowMs: Double) -> String {
        "{\"type\":\"ping\",\"t\":\(format(nowMs)),"
            + "\"droppedFramesMac\":\(droppedFramesMac),"
            + "\"queueDepthMac\":\(queueDepthMac),"
            + "\"pendingEncodesMac\":\(pendingEncodesMac),"
            + "\"totalPendingWorkMac\":\(totalPendingWorkMac),"
            + "\"pendingEncodePeak\":\(pendingEncodePeak),"
            + "\"capFps\":\(captureFps),"
            + "\"requestedFps\":\(requestedFps),"
            + "\"actualVirtualDisplayRefreshRate\":\(actualVirtualDisplayRefreshRate),"
            + "\"encodedFps\":\(encodedFps),"
            + "\"sentFps\":\(sentFps),"
            + "\"averageFrameSize\":\(averageFrameSize),"
            + "\"encodeLatencyMs\":\(format(encodeLatencyMs)),"
            + "\"bitrate\":\(bitrate),"
            + "\"inp50\":\(format(inputP50Ms)),"
            + "\"inp95\":\(format(inputP95Ms))}"
    }

    private func format(_ value: Double) -> String {
        String(format: "%.3f", value)
    }
}

struct StreamConfigMessage {
    var codec: StreamCodec
    var fps: Int
    var width: Int
    var height: Int
    var bitrate: Int
    var transport: String
    var identity: StreamProtocolFrameIdentity? = nil
    var maxFrameBytes: Int? = nil

    var profile: String {
        codec == .hevc ? "main" : "high"
    }

    var json: String {
        let legacy = "{\"type\":\"streamConfig\","
            + "\"codec\":\"\(codec.rawValue)\","
            + "\"fps\":\(RefreshRatePolicy.sanitize(fps)),"
            + "\"width\":\(max(width, 1)),"
            + "\"height\":\(max(height, 1)),"
            + "\"bitrate\":\(max(bitrate, 0)),"
            + "\"profile\":\"\(profile)\","
            + "\"transport\":\"\(escaped(transport))\""
        guard let identity else { return legacy + "}" }
        var negotiated = legacy
            + ",\"protocolVersion\":2"
            + ",\"sessionEpoch\":\(identity.sessionEpoch)"
            + ",\"configVersion\":\(identity.configVersion)"
        if let maxFrameBytes, maxFrameBytes > 0 {
            negotiated += ",\"maxFrameBytes\":\(min(maxFrameBytes, FrameSizePolicy.absoluteMaxBytes))"
        }
        return negotiated + "}"
    }

    private func escaped(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}

struct StreamProtocolFrameIdentity: Equatable, Sendable {
    let sessionEpoch: Int64
    let configVersion: Int64
    let frameSequence: Int64
}

final class StreamSessionEpochAllocator: @unchecked Sendable {
    static let process = StreamSessionEpochAllocator()

    private let lock = NSLock()
    private var lastEpoch: Int64 = 0

    func next() -> Int64 {
        lock.lock()
        defer { lock.unlock() }
        lastEpoch = lastEpoch == Int64.max ? 1 : lastEpoch + 1
        return lastEpoch
    }
}

struct StreamProtocolIdentity: Sendable {
    private let epochAllocator: StreamSessionEpochAllocator
    private(set) var sessionEpoch: Int64 = 0
    private(set) var configVersion: Int64 = 0
    private(set) var frameSequence: Int64 = 0

    init(epochAllocator: StreamSessionEpochAllocator = .process) {
        self.epochAllocator = epochAllocator
    }

    mutating func beginConnection() {
        sessionEpoch = epochAllocator.next()
        configVersion = 0
        frameSequence = 0
    }

    mutating func beginConfiguration() -> StreamProtocolFrameIdentity {
        if sessionEpoch == 0 { beginConnection() }
        configVersion += 1
        frameSequence = 0
        return current
    }

    mutating func nextFrame() -> StreamProtocolFrameIdentity {
        frameSequence += 1
        return current
    }

    var current: StreamProtocolFrameIdentity {
        StreamProtocolFrameIdentity(
            sessionEpoch: sessionEpoch,
            configVersion: configVersion,
            frameSequence: frameSequence)
    }
}

enum VideoTelemetryPrefix {
    static func json(captureMs: Int64, sendMs: Int64,
                     identity: StreamProtocolFrameIdentity?) -> String {
        guard let identity else {
            return "{\"cap\":\(captureMs),\"snd\":\(sendMs)}"
        }
        return "{\"cap\":\(captureMs),\"snd\":\(sendMs),"
            + "\"se\":\(identity.sessionEpoch),\"cv\":\(identity.configVersion),"
            + "\"fs\":\(identity.frameSequence)}"
    }
}

enum ReceiverProtocolHandshakePhase: Equatable, Sendable {
    case idle
    case awaitingStreamConfigAck
    case awaitingDecoderReady
    case awaitingFirstFrame
    case streaming
    case failed
}

enum ReceiverProtocolTimeoutAction: Equatable, Sendable {
    case none
    case retry
    case fail
}

struct ReceiverProtocolHandshake: Sendable {
    private(set) var phase: ReceiverProtocolHandshakePhase = .idle
    private(set) var identity: StreamProtocolFrameIdentity?
    private var timeoutCount = 0

    mutating func begin(_ identity: StreamProtocolFrameIdentity) {
        self.identity = identity
        phase = .awaitingStreamConfigAck
        timeoutCount = 0
    }

    mutating func retrying(_ identity: StreamProtocolFrameIdentity) {
        self.identity = identity
        phase = .awaitingStreamConfigAck
    }

    mutating func receive(type: String, identity candidate: StreamProtocolFrameIdentity) -> Bool {
        guard candidate.sessionEpoch == identity?.sessionEpoch,
              candidate.configVersion == identity?.configVersion else {
            return false
        }
        switch (phase, type) {
        case (.awaitingStreamConfigAck, "streamConfigAck"):
            phase = .awaitingDecoderReady
        case (.awaitingDecoderReady, "decoderReady"):
            phase = .awaitingFirstFrame
        case (.awaitingFirstFrame, "firstFrameRendered") where candidate.frameSequence > 0:
            phase = .streaming
        default:
            return false
        }
        return true
    }

    mutating func timeoutAction() -> ReceiverProtocolTimeoutAction {
        guard phase != .idle, phase != .streaming, phase != .failed else { return .none }
        if timeoutCount < 2 {
            timeoutCount += 1
            return .retry
        }
        phase = .failed
        return .fail
    }
}

enum ReceiverProtocolFailureAction: Equatable, Sendable {
    case reconnect
    case endSession
}

enum ReceiverDecoderRecoveryAction: Equatable, Sendable {
    case resendStreamConfig
    case forceKeyframe
}

enum ReceiverDecoderRecoveryPolicy {
    static func actions(
        negotiatedV2: Bool,
        streamConfigRequired: Bool
    ) -> [ReceiverDecoderRecoveryAction] {
        if negotiatedV2 && streamConfigRequired {
            return [.resendStreamConfig, .forceKeyframe]
        }
        return [.forceKeyframe]
    }
}

struct ReceiverProtocolFailureBudget: Sendable {
    let maxReconnects: Int
    private var reconnects = 0

    init(maxReconnects: Int) {
        self.maxReconnects = max(0, maxReconnects)
    }

    mutating func failureAction() -> ReceiverProtocolFailureAction {
        guard reconnects < maxReconnects else { return .endSession }
        reconnects += 1
        return .reconnect
    }

    mutating func markStreaming() {
        reconnects = 0
    }
}

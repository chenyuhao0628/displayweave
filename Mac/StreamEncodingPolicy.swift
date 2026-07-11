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
                        quality: StreamQuality = .high) -> Int {
        let sanitizedFps = RefreshRatePolicy.sanitize(fps)
        let megapixels = max(1.0, Double(width * height) / 1_000_000.0)
        let mbps: Double
        switch codec {
        case .hevc:
            mbps = megapixels * Double(sanitizedFps) * 0.12
        case .h264:
            mbps = megapixels * Double(sanitizedFps) * 0.10
        }
        let roundedMbps = Int((mbps * quality.bitrateMultiplier).rounded())
        let clampedMbps: Int
        switch codec {
        case .hevc:
            clampedMbps = min(max(roundedMbps, 12), 80)
        case .h264:
            clampedMbps = min(max(roundedMbps, 8), 30)
        }
        return clampedMbps * 1_000_000
    }

    static func keyframeInterval(fps: Int) -> Int {
        RefreshRatePolicy.sanitize(fps)
    }

    /// Candidate defaults pending physical-device GOP A/B validation.
    static func keyframeInterval(fps: Int, transport: BitrateTransport) -> Int {
        RefreshRatePolicy.sanitize(fps) * (transport == .wifi ? 2 : 1)
    }

    static func frameDurationTimescale(fps: Int) -> Int {
        RefreshRatePolicy.sanitize(fps)
    }
}

struct StreamDebugStats {
    var droppedFramesMac: Int
    var queueDepthMac: Int
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

    var profile: String {
        codec == .hevc ? "main" : "high"
    }

    var json: String {
        "{\"type\":\"streamConfig\","
            + "\"codec\":\"\(codec.rawValue)\","
            + "\"fps\":\(RefreshRatePolicy.sanitize(fps)),"
            + "\"width\":\(max(width, 1)),"
            + "\"height\":\(max(height, 1)),"
            + "\"bitrate\":\(max(bitrate, 0)),"
            + "\"profile\":\"\(profile)\","
            + "\"transport\":\"\(escaped(transport))\"}"
    }

    private func escaped(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}

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

enum StreamEncodingPolicy {
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

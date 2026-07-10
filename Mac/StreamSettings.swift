import Foundation

/// Capture-resolution / bitrate trade-off. The virtual display always runs at
/// native size; only the captured/encoded stream is scaled.
enum StreamQuality: String, CaseIterable {
    case low, balanced, high, gaming

    var scale: Double {
        switch self {
        case .low: return 0.5
        case .balanced: return 0.75
        case .high: return 1.0
        case .gaming: return 0.75
        }
    }

    var bitrateMultiplier: Double {
        switch self {
        case .low: return 0.55
        case .balanced: return 0.75
        case .high: return 1.0
        case .gaming: return 0.85
        }
    }

    var label: String {
        switch self {
        case .low: return "Low"
        case .balanced: return "Balanced"
        case .high: return "High"
        case .gaming: return "Gaming"
        }
    }

    var explanation: String {
        switch self {
        case .low: return "半分辨率和较低码率，优先降低 WiFi 带宽占用。"
        case .balanced: return "75% 分辨率和均衡码率，兼顾清晰度与延迟。"
        case .high: return "原生分辨率和完整码率，优先保证画面细节。"
        case .gaming: return "75% 分辨率和偏高码率，优先保持高帧率与低排队延迟。"
        }
    }

    static func fromStoredValue(_ value: String?) -> StreamQuality {
        switch value?.lowercased() {
        case "low", "fast": return .low
        case "balanced": return .balanced
        case "high", "best": return .high
        case "gaming": return .gaming
        default: return .high
        }
    }
}

enum StreamFpsMode: String, CaseIterable {
    case auto
    case fps60
    case fps90
    case fps120

    var label: String {
        switch self {
        case .auto: return "Auto"
        case .fps60: return "60"
        case .fps90: return "90"
        case .fps120: return "120"
        }
    }

    var userSelectedFps: Int? {
        switch self {
        case .auto: return nil
        case .fps60: return 60
        case .fps90: return 90
        case .fps120: return 120
        }
    }
}

enum StreamCodecMode: String, CaseIterable {
    case auto
    case hevc
    case h264

    var label: String {
        switch self {
        case .auto: return "Auto"
        case .hevc: return "HEVC"
        case .h264: return "H.264"
        }
    }

    var codecOverride: StreamCodec? {
        switch self {
        case .auto: return nil
        case .hevc: return .hevc
        case .h264: return .h264
        }
    }
}

enum StreamTransportMode: String, CaseIterable {
    case wifi

    var label: String {
        switch self {
        case .wifi: return "WiFi"
        }
    }
}

struct StreamSettings: Equatable {
    var fpsMode: StreamFpsMode
    var codecMode: StreamCodecMode
    var quality: StreamQuality
    var transportMode: StreamTransportMode
    var enableDebugStats: Bool

    static func load(from defaults: UserDefaults = .standard) -> StreamSettings {
        let fpsMode = StreamFpsMode(rawValue: defaults.string(forKey: "fpsMode") ?? "") ?? legacyFpsMode(defaults)
        let codecMode = StreamCodecMode(rawValue: defaults.string(forKey: "codecMode") ?? "") ?? legacyCodecMode(defaults)
        let quality = StreamQuality.fromStoredValue(defaults.string(forKey: "quality"))
        let transportMode = StreamTransportMode(rawValue: defaults.string(forKey: "transportMode") ?? "") ?? .wifi
        let debugStats = defaults.object(forKey: "debugStats") == nil || defaults.bool(forKey: "debugStats")
        return StreamSettings(
            fpsMode: fpsMode,
            codecMode: codecMode,
            quality: quality,
            transportMode: transportMode,
            enableDebugStats: debugStats)
    }

    func save(to defaults: UserDefaults = .standard) {
        defaults.set(fpsMode.rawValue, forKey: "fpsMode")
        defaults.set(codecMode.rawValue, forKey: "codecMode")
        defaults.set(quality.rawValue, forKey: "quality")
        defaults.set(transportMode.rawValue, forKey: "transportMode")
        defaults.set(enableDebugStats, forKey: "debugStats")
    }

    func selectedFps(deviceMaxFps: Int) -> Int {
        RefreshRatePolicy.selected(deviceMaxFps: deviceMaxFps, userSelectedFps: fpsMode.userSelectedFps)
    }

    func selectedCodec(supportedCodecs: [String], preferredCodec: String?) -> StreamCodec {
        codecMode.codecOverride
            ?? StreamEncodingPolicy.selectedCodec(
                supportedCodecs: supportedCodecs,
                preferredCodec: preferredCodec)
    }

    private static func legacyFpsMode(_ defaults: UserDefaults) -> StreamFpsMode {
        guard defaults.object(forKey: "fps") != nil else { return .auto }
        switch RefreshRatePolicy.sanitize(defaults.integer(forKey: "fps")) {
        case 120: return .fps120
        case 90: return .fps90
        case 60: return .fps60
        default: return .auto
        }
    }

    private static func legacyCodecMode(_ defaults: UserDefaults) -> StreamCodecMode {
        switch defaults.string(forKey: "codec")?.lowercased() {
        case StreamCodec.hevc.rawValue: return .hevc
        case StreamCodec.h264.rawValue: return .h264
        default: return .auto
        }
    }
}

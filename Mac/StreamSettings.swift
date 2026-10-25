import Foundation

/// Capture-resolution / bitrate trade-off. Desktop mode is configured separately;
/// only the captured/encoded stream is scaled by this setting.
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
        case .low: return "省流"
        case .balanced: return "均衡"
        case .high: return "清晰"
        case .gaming: return "流畅"
        }
    }

    var explanation: String {
        switch self {
        case .low: return "半分辨率和较低码率，优先降低 WiFi 带宽占用。"
        case .balanced: return "75% 分辨率和均衡码率，兼顾清晰度与延迟。"
        case .high: return "按所选桌面分辨率编码（受接收上限约束）和完整码率，优先保证画面细节。"
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
    case fps30
    case fps60
    case fps90
    case fps120

    var label: String {
        switch self {
        case .auto: return "自动"
        case .fps30: return "30"
        case .fps60: return "60"
        case .fps90: return "90"
        case .fps120: return "120"
        }
    }

    var userSelectedFps: Int? {
        switch self {
        case .auto: return nil
        case .fps30: return 30
        case .fps60: return 60
        case .fps90: return 90
        case .fps120: return 120
        }
    }
}

enum StreamPriority: String, CaseIterable {
    case resolution, frameRate
    var label: String { self == .resolution ? "分辨率优先" : "帧率优先" }
}

enum StreamCodecMode: String, CaseIterable {
    case auto
    case hevc
    case h264

    var label: String {
        switch self {
        case .auto: return "自动"
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
    case auto
    case usb
    case wifi

    var label: String {
        switch self {
        case .auto: return "自动"
        case .usb: return "USB"
        case .wifi: return "局域网"
        }
    }
}

enum BitrateMode: String, CaseIterable {
    case auto, manual, benchmark

    var label: String {
        switch self {
        case .auto: return "自动"
        case .manual: return "手动"
        case .benchmark: return "测试"
        }
    }
}

enum BitratePreset: Int, CaseIterable {
    case mbps10 = 10, mbps20 = 20, mbps30 = 30, mbps40 = 40
    case mbps60 = 60, mbps80 = 80, mbps100 = 100, mbps120 = 120
    case mbps140 = 140, mbps160 = 160, mbps180 = 180, mbps200 = 200

    var megabits: Int { rawValue }
    var bitsPerSecond: Int { rawValue * 1_000_000 }
    var label: String { "\(rawValue) Mbps" }

    static var manualCases: [BitratePreset] {
        allCases.filter { $0.rawValue <= 160 && $0 != .mbps140 }
    }
    static var benchmarkCases: [BitratePreset] { allCases }
}

struct StreamSettings: Equatable {
    var fpsMode: StreamFpsMode
    var codecMode: StreamCodecMode
    var quality: StreamQuality
    var transportMode: StreamTransportMode
    var enableDebugStats: Bool
    var bitrateMode: BitrateMode = .auto
    var bitratePreset: BitratePreset = .mbps40
    var desktopResolutions = DesktopResolutionPreferences()
    var priority: StreamPriority = .resolution

    var availableBitratePresets: [BitratePreset] {
        guard bitrateMode != .auto else { return [] }
        if bitrateMode == .benchmark { return BitratePreset.benchmarkCases }
        let codecs: [StreamCodec] = codecMode.codecOverride.map { [$0] } ?? [.h264, .hevc]
        let transports: [BitrateTransport] = transportMode == .auto ? [.wifi, .usb] : [transportMode == .usb ? .usb : .wifi]
        return BitratePreset.manualCases.filter { preset in
            codecs.contains { codec in transports.contains { transport in
                StreamEncodingPolicy.bitrateBounds(codec: codec, transport: transport).contains(preset.bitsPerSecond)
            } }
        }
    }

    mutating func normalizeBitratePreset() {
        let available = availableBitratePresets
        guard !available.isEmpty, !available.contains(bitratePreset) else { return }
        bitratePreset = available.min { abs($0.rawValue - bitratePreset.rawValue) < abs($1.rawValue - bitratePreset.rawValue) }!
    }

    static func load(from defaults: UserDefaults = .standard) -> StreamSettings {
        let fpsMode = StreamFpsMode(rawValue: defaults.string(forKey: "fpsMode") ?? "") ?? legacyFpsMode(defaults)
        let codecMode = StreamCodecMode(rawValue: defaults.string(forKey: "codecMode") ?? "") ?? legacyCodecMode(defaults)
        let quality = StreamQuality.fromStoredValue(defaults.string(forKey: "quality"))
        let transportMode = StreamTransportMode(rawValue: defaults.string(forKey: "transportMode") ?? "") ?? .auto
        let debugStats = defaults.object(forKey: "debugStats") == nil || defaults.bool(forKey: "debugStats")
        let storedBitrateMode = defaults.string(forKey: "bitrateMode")
        let bitrateMode = BitrateMode(rawValue: storedBitrateMode ?? "") ?? .auto
        let bitratePreset = BitratePreset(rawValue: defaults.integer(forKey: "bitrateMbps")) ?? .mbps40
        var settings = StreamSettings(
            fpsMode: fpsMode,
            codecMode: codecMode,
            quality: quality,
            transportMode: transportMode,
            enableDebugStats: debugStats,
            bitrateMode: bitrateMode,
            bitratePreset: bitratePreset,
            desktopResolutions: DesktopResolutionPreferences(
                stored: defaults.dictionary(forKey: "desktopResolutions.v1") as? [String: String] ?? [:]),
            priority: StreamPriority(rawValue: defaults.string(forKey: "streamPriority") ?? "") ?? .resolution)
        settings.normalizeBitratePreset()
        return settings
    }

    func save(to defaults: UserDefaults = .standard) {
        defaults.set(fpsMode.rawValue, forKey: "fpsMode")
        defaults.set(codecMode.rawValue, forKey: "codecMode")
        defaults.set(quality.rawValue, forKey: "quality")
        defaults.set(transportMode.rawValue, forKey: "transportMode")
        defaults.set(enableDebugStats, forKey: "debugStats")
        defaults.set(bitrateMode.rawValue, forKey: "bitrateMode")
        defaults.set(bitratePreset.rawValue, forKey: "bitrateMbps")
        defaults.set(desktopResolutions.stored, forKey: "desktopResolutions.v1")
        defaults.set(priority.rawValue, forKey: "streamPriority")
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
        case 30: return defaults.integer(forKey: "fps") == 30 ? .fps30 : .auto
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

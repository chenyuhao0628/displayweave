import Foundation

struct PhoneInfo: Decodable {
    let pixelsWide: Int
    let pixelsHigh: Int
    let scale: Double
    let device: String?
    let id: String?
    let refreshRate: Int?
    let maxFps: Int?
    let supportedCodecs: [String]?
    let preferredCodec: String?
    let deviceModel: String?
    let androidSdk: Int?
    let transport: String?

    var kind: String { device ?? "设备" }
    var negotiatedRefreshRate: Int { Self.supportedFpsBucket(refreshRate ?? 60) }
    var negotiatedMaxFps: Int { Self.supportedFpsBucket(maxFps ?? negotiatedRefreshRate) }
    var negotiatedSupportedCodecs: [String] {
        let normalized = (supportedCodecs ?? ["h264"]).map { $0.lowercased() }
        return normalized.isEmpty ? ["h264"] : normalized
    }
    var negotiatedPreferredCodec: String {
        let preferred = (preferredCodec ?? "h264").lowercased()
        return negotiatedSupportedCodecs.contains(preferred) ? preferred : "h264"
    }
    var negotiatedDeviceModel: String { deviceModel ?? kind }
    var negotiatedAndroidSdk: Int { androidSdk ?? 0 }
    var negotiatedTransport: String { transport ?? "unknown" }

    private static func supportedFpsBucket(_ value: Int) -> Int {
        if value >= 110 { return 120 }
        if value >= 80 { return 90 }
        if value >= 45 { return 60 }
        return 30
    }
}

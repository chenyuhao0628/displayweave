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
    let protocolVersion: Int?
    let capabilities: [String]?
    let maxFrameBytes: Int?

    let panel: PanelAnnouncement?
    let videoCaps: [VideoCapability]?
    let displayMaxFrameRate: Int?
    let maxEncodeWide: Int?
    let maxEncodeHigh: Int?
    /// Validate peer-controlled geometry before multiplication or capture setup.
    var hasValidGeometry: Bool {
        func valid(_ width: Int, _ height: Int, _ scale: Double) -> Bool {
            (2...16384).contains(width) && (2...16384).contains(height)
                && width * height <= 67_108_864 && scale.isFinite && scale > 0 && scale <= 4
        }
        guard valid(pixelsWide, pixelsHigh, scale) else { return false }
        if let panel {
            guard valid(panel.pixelsWide, panel.pixelsHigh, panel.scale) else { return false }
            if let width = panel.pointsWide, !(2...16384).contains(width) { return false }
            if let height = panel.pointsHigh, !(2...16384).contains(height) { return false }
        }
        return true
    }

    var isMacReceiver: Bool { device?.lowercased() == "mac" }

    func sameDisplayConfiguration(as other: PhoneInfo) -> Bool {
        pixelsWide == other.pixelsWide && pixelsHigh == other.pixelsHigh
            && (!isMacReceiver || (scale == other.scale && panel == other.panel
                && videoCaps == other.videoCaps && displayMaxFrameRate == other.displayMaxFrameRate
                && maxEncodeWide == other.maxEncodeWide && maxEncodeHigh == other.maxEncodeHigh))
    }

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
    var isAndroidReceiver: Bool {
        kind.lowercased() == "android" || (androidSdk ?? 0) > 0
    }
    var supportsProtocolV2: Bool {
        guard isAndroidReceiver, (protocolVersion ?? 1) >= 2 else {
            return false
        }
        let advertised = Set(capabilities ?? [])
        let required: Set<String> = [
            "streamConfigAck", "decoderReady", "firstFrameRendered",
            "sessionEpoch", "configVersion", "frameSequence"
        ]
        return required.isSubset(of: advertised)
    }
    var supportsBinaryFrameHeaderV2: Bool {
        supportsProtocolV2
            && Set(capabilities ?? []).contains("binaryFrameHeaderV2")
    }
    var negotiatedMaxFrameBytes: Int? {
        FrameSizePolicy.negotiatedMaxBytes(
            supportsProtocolV2: supportsProtocolV2,
            capabilities: capabilities ?? [],
            advertisedBytes: maxFrameBytes)
    }

    private static func supportedFpsBucket(_ value: Int) -> Int {
        if value >= 110 { return 120 }
        if value >= 80 { return 90 }
        if value >= 45 { return 60 }
        return 30
    }
}

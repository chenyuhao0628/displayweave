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
    let inputCaps: [String]?
    let maxFrameBytes: Int?
    let udpMediaV1: Bool?
    let udpPort: Int?

    let panel: PanelAnnouncement?
    let videoCaps: [VideoCapability]?
    let displayMaxFrameRate: Int?
    let maxEncodeWide: Int?
    let maxEncodeHigh: Int?

    private enum CodingKeys: String, CodingKey {
        case pixelsWide, pixelsHigh, scale, device, id, refreshRate, maxFps
        case supportedCodecs, preferredCodec, deviceModel, androidSdk, transport
        case protocolVersion, capabilities, inputCaps, maxFrameBytes, udpMediaV1, udpPort
        case panel, videoCaps, displayMaxFrameRate, maxEncodeWide, maxEncodeHigh
    }

    private struct PartialPanelMillimeters: Decodable {
        let pixelsWide: Int?
        let pixelsHigh: Int?
        let millimetersWide: Double?
        let millimetersHigh: Double?
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        pixelsWide = try values.decode(Int.self, forKey: .pixelsWide)
        pixelsHigh = try values.decode(Int.self, forKey: .pixelsHigh)
        scale = try values.decode(Double.self, forKey: .scale)
        device = try values.decodeIfPresent(String.self, forKey: .device)
        id = try values.decodeIfPresent(String.self, forKey: .id)
        refreshRate = try values.decodeIfPresent(Int.self, forKey: .refreshRate)
        maxFps = try values.decodeIfPresent(Int.self, forKey: .maxFps)
        supportedCodecs = try values.decodeIfPresent([String].self, forKey: .supportedCodecs)
        preferredCodec = try values.decodeIfPresent(String.self, forKey: .preferredCodec)
        deviceModel = try values.decodeIfPresent(String.self, forKey: .deviceModel)
        androidSdk = try values.decodeIfPresent(Int.self, forKey: .androidSdk)
        transport = try values.decodeIfPresent(String.self, forKey: .transport)
        protocolVersion = try values.decodeIfPresent(Int.self, forKey: .protocolVersion)
        capabilities = try values.decodeIfPresent([String].self, forKey: .capabilities)
        inputCaps = try values.decodeIfPresent([String].self, forKey: .inputCaps)
        maxFrameBytes = try values.decodeIfPresent(Int.self, forKey: .maxFrameBytes)
        udpMediaV1 = try values.decodeIfPresent(Bool.self, forKey: .udpMediaV1)
        udpPort = try values.decodeIfPresent(Int.self, forKey: .udpPort)
        videoCaps = try values.decodeIfPresent([VideoCapability].self, forKey: .videoCaps)
        displayMaxFrameRate = try values.decodeIfPresent(Int.self, forKey: .displayMaxFrameRate)
        maxEncodeWide = try values.decodeIfPresent(Int.self, forKey: .maxEncodeWide)
        maxEncodeHigh = try values.decodeIfPresent(Int.self, forKey: .maxEncodeHigh)

        if values.contains(.panel) {
            if let fullPanel = try? values.decodeIfPresent(PanelAnnouncement.self, forKey: .panel) {
                panel = fullPanel
            } else if let partial = try? values.decodeIfPresent(PartialPanelMillimeters.self, forKey: .panel),
                      partial.pixelsWide == nil, partial.pixelsHigh == nil {
                func clampInt(_ v: Double?) -> Int? {
                    guard let v, v.isFinite, v >= Double(Int.min), v <= Double(Int.max) else { return nil }
                    return Int(v.rounded())
                }
                let safeScale = scale.isFinite ? min(max(scale, 0.1), 4.0) : 2.0
                panel = PanelAnnouncement(
                    pixelsWide: pixelsWide,
                    pixelsHigh: pixelsHigh,
                    scale: safeScale,
                    millimetersWide: clampInt(partial.millimetersWide),
                    millimetersHigh: clampInt(partial.millimetersHigh))
            } else {
                panel = nil
            }
        } else {
            panel = nil
        }
    }
    /// Validate peer-controlled geometry before multiplication or capture setup.
    var hasValidGeometry: Bool {
        func valid(_ width: Int, _ height: Int, _ scale: Double) -> Bool {
            (2...16384).contains(width) && (2...16384).contains(height)
                && width * height <= 67_108_864 && scale.isFinite && scale > 0 && scale <= 4
        }
        guard valid(pixelsWide, pixelsHigh, scale) else { return false }
        if usesAppleVideoCapabilities {
            if let limit = maxEncodeWide, !(2...16384).contains(limit) { return false }
            if let limit = maxEncodeHigh, !(2...16384).contains(limit) { return false }
            if let fps = displayMaxFrameRate, !(1...240).contains(fps) { return false }
            if let caps = videoCaps {
                guard !caps.isEmpty, caps.count <= 16,
                      caps.contains(where: { $0.codec.lowercased() == "h264" }) else { return false }
                for cap in caps {
                    if let value = cap.maxWidth, !(2...16384).contains(value) { return false }
                    if let value = cap.maxHeight, !(2...16384).contains(value) { return false }
                    if let value = cap.maxFrameRate, !(1...240).contains(value) { return false }
                    if let value = cap.maxPixelsPerSecond, !(4...(67_108_864 * 240)).contains(value) { return false }
                }
            }
        }
        if let panel {
            guard valid(panel.pixelsWide, panel.pixelsHigh, panel.scale) else { return false }
            if let width = panel.pointsWide, !(2...16384).contains(width) { return false }
            if let height = panel.pointsHigh, !(2...16384).contains(height) { return false }
        }
        return true
    }

    var isMacReceiver: Bool { device?.lowercased() == "mac" }
    var usesAppleVideoCapabilities: Bool {
        isMacReceiver || (!isAndroidReceiver && (capabilities ?? []).contains("appleVideoV1"))
    }

    func sameDisplayConfiguration(as other: PhoneInfo) -> Bool {
        pixelsWide == other.pixelsWide && pixelsHigh == other.pixelsHigh
            && panel == other.panel
            && (!usesAppleVideoCapabilities || (scale == other.scale
                && supportedCodecs == other.supportedCodecs && videoCaps == other.videoCaps && displayMaxFrameRate == other.displayMaxFrameRate
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
    var supportsUDPMediaV1: Bool {
        udpMediaV1 == true || Set(capabilities ?? []).contains("udpMediaV1")
    }
    var advertisedUDPPort: UInt16? {
        guard let udpPort, (1...65535).contains(udpPort) else { return nil }
        return UInt16(udpPort)
    }

    private static func supportedFpsBucket(_ value: Int) -> Int {
        if value >= 110 { return 120 }
        if value >= 80 { return 90 }
        if value >= 45 { return 60 }
        return 30
    }
}

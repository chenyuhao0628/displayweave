import Foundation

func assertEqual(_ expected: Int?, _ actual: Int?, _ message: String) {
    if expected != actual {
        fatalError("\(message): expected \(String(describing: expected)), got \(String(describing: actual))")
    }
}

func assertEqual(_ expected: StreamCodec?, _ actual: StreamCodec?, _ message: String) {
    if expected != actual {
        fatalError("\(message): expected \(String(describing: expected)), got \(String(describing: actual))")
    }
}

func assertEqual(_ expected: StreamCodec, _ actual: StreamCodec, _ message: String) {
    if expected != actual {
        fatalError("\(message): expected \(expected), got \(actual)")
    }
}

func assertEqual(_ expected: StreamQuality, _ actual: StreamQuality, _ message: String) {
    if expected != actual {
        fatalError("\(message): expected \(expected), got \(actual)")
    }
}

func assertTrue(_ value: Bool, _ message: String) {
    if !value {
        fatalError(message)
    }
}

@main
struct StreamSettingsSelfTest {
    static func main() {
        let suiteName = "StreamSettingsSelfTest.\(UUID().uuidString)"
        let emptyDefaults = UserDefaults(suiteName: suiteName)!
        defer { emptyDefaults.removePersistentDomain(forName: suiteName) }

        assertTrue(StreamTransportMode.allCases.map(\.rawValue) == ["auto", "usb", "wifi"],
                   "transport modes remain Auto, USB, WiFi in priority order")
        assertTrue(StreamSettings.load(from: emptyDefaults).transportMode == .auto,
                   "new installs default transport to Auto")

        assertTrue(StreamQuality.allCases.map(\.rawValue) == ["low", "balanced", "high", "gaming"],
                   "quality settings expose Low/Balanced/High/Gaming in a stable order")
        assertEqual(.high, StreamQuality.fromStoredValue("best"),
                    "legacy Best quality migrates to High")
        assertEqual(.low, StreamQuality.fromStoredValue("fast"),
                    "legacy Fast quality migrates to Low")

        assertEqual(nil, StreamFpsMode.auto.userSelectedFps,
                    "auto fps does not force a user fps")
        assertEqual(90, StreamFpsMode.fps90.userSelectedFps,
                    "90fps mode maps to an explicit fps")

        assertEqual(nil, StreamCodecMode.auto.codecOverride,
                    "auto codec does not force a codec")
        assertEqual(.hevc, StreamCodecMode.hevc.codecOverride,
                    "HEVC mode maps to HEVC")

        let auto = StreamSettings(
            fpsMode: .auto,
            codecMode: .auto,
            quality: .balanced,
            transportMode: .wifi,
            enableDebugStats: true)
        assertEqual(120, auto.selectedFps(deviceMaxFps: 120),
                    "auto fps follows device max")
        assertEqual(.hevc,
                    auto.selectedCodec(supportedCodecs: ["h264", "hevc"], preferredCodec: "hevc"),
                    "auto codec follows negotiated HEVC")

        let forced = StreamSettings(
            fpsMode: .fps120,
            codecMode: .h264,
            quality: .gaming,
            transportMode: .wifi,
            enableDebugStats: false)
        assertEqual(60, forced.selectedFps(deviceMaxFps: 60),
                    "device max still caps forced fps")
        assertEqual(.h264,
                    forced.selectedCodec(supportedCodecs: ["h264", "hevc"], preferredCodec: "hevc"),
                    "forced H.264 overrides negotiated HEVC")

        print("StreamSettingsSelfTest PASS")
    }
}

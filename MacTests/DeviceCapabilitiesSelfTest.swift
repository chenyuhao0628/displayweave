import Foundation

func assertEqual<T: Equatable>(_ expected: T, _ actual: T, _ message: String) {
    if expected != actual {
        fatalError("\(message): expected \(expected), got \(actual)")
    }
}

@main
struct DeviceCapabilitiesSelfTest {
    static func main() throws {
        let oldHello = try JSONDecoder().decode(PhoneInfo.self, from: Data("""
        {"type":"hello","pixelsWide":1920,"pixelsHigh":1080,"scale":2.0,"device":"Android"}
        """.utf8))
        assertEqual(60, oldHello.negotiatedRefreshRate,
                    "old hello defaults display refresh to 60Hz")
        assertEqual(60, oldHello.negotiatedMaxFps,
                    "old hello defaults max fps to 60")
        assertEqual(["h264"], oldHello.negotiatedSupportedCodecs,
                    "old hello defaults codec support to H.264")
        assertEqual("h264", oldHello.negotiatedPreferredCodec,
                    "old hello defaults preferred codec to H.264")

        let modernHello = try JSONDecoder().decode(PhoneInfo.self, from: Data("""
        {"type":"hello","pixelsWide":2560,"pixelsHigh":1600,"scale":2.0,
         "refreshRate":120,"maxFps":120,"supportedCodecs":["HEVC","H264"],
         "preferredCodec":"HEVC","deviceModel":"Android Tablet","androidSdk":35,
         "transport":"wifi"}
        """.utf8))
        assertEqual(120, modernHello.negotiatedRefreshRate,
                    "modern hello preserves 120Hz display capability")
        assertEqual(120, modernHello.negotiatedMaxFps,
                    "modern hello preserves 120fps capability")
        assertEqual(["hevc", "h264"], modernHello.negotiatedSupportedCodecs,
                    "codec names are normalized")
        assertEqual("hevc", modernHello.negotiatedPreferredCodec,
                    "supported HEVC preference is preserved")
        assertEqual("wifi", modernHello.negotiatedTransport,
                    "transport metadata is preserved")

        let unsupportedPreference = try JSONDecoder().decode(PhoneInfo.self, from: Data("""
        {"pixelsWide":1280,"pixelsHigh":720,"scale":1.0,
         "maxFps":144,"supportedCodecs":["h264"],"preferredCodec":"vp9"}
        """.utf8))
        assertEqual(120, unsupportedPreference.negotiatedMaxFps,
                    "reported refresh values are bucketed to supported fps")
        assertEqual("h264", unsupportedPreference.negotiatedPreferredCodec,
                    "unsupported codec preference falls back to H.264")

        print("DeviceCapabilitiesSelfTest PASS")
    }
}

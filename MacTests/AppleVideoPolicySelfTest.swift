import Foundation

@main enum AppleVideoPolicySelfTest {
    static func main() throws {
        precondition(AppleVideoPolicy.frameRate(maximum: 120) == 120)
        precondition(AppleVideoPolicy.frameRate(maximum: 119) == 90)
        precondition(AppleVideoPolicy.frameRate(maximum: 59) == 30)
        precondition(AppleVideoPolicy.frameRate(maximum: 24) == 24)
        let valid: [String: Any] = ["codec": "hevc", "width": 1920, "height": 1080, "fps": 120]
        precondition(AppleVideoConfiguration(valid, maxWidth: 4096, maxHeight: 2304, maxFps: 120) != nil)
        for patch: [String: Any] in [["width": 1919], ["height": Int.max], ["fps": 121], ["codec": "bad"], ["width": -2]] {
            precondition(AppleVideoConfiguration(valid.merging(patch) { _, b in b },
                maxWidth: 4096, maxHeight: 2304, maxFps: 120) == nil)
        }
        precondition(AppleVideoConfiguration(valid, maxWidth: 4096, maxHeight: 2304, maxFps: 60) == nil)
        let hello = #"{"pixelsWide":1920,"pixelsHigh":1080,"scale":2,"device":"iPad","capabilities":["appleVideoV1"],"supportedCodecs":["h264","hevc"],"displayMaxFrameRate":120,"videoCaps":[{"codec":"h264","maxWidth":4096,"maxHeight":2304,"maxFrameRate":120,"maxPixelsPerSecond":566231040},{"codec":"hevc","maxWidth":4096,"maxHeight":2304,"maxFrameRate":120,"maxPixelsPerSecond":566231040}]}"#
        let info = try JSONDecoder().decode(PhoneInfo.self, from: Data(hello.utf8))
        precondition(info.usesAppleVideoCapabilities && !info.supportsProtocolV2)
        let settings = StreamSettings(fpsMode: .auto, codecMode: .auto, quality: .high,
                                      transportMode: .auto, enableDebugStats: true)
        let plan = MacReceiverPolicy.plan(info: info, settings: settings, hardwareHEVCEncode: true)
        precondition(plan.fps == 120 && plan.codec == .hevc)
        let large = MacReceiverPolicy.plan(info: info, settings: settings,
            sourceWidth: 4096, sourceHeight: 2304, hardwareHEVCEncode: true)
        precondition(large.fps == 60)
        let legacy = try JSONDecoder().decode(PhoneInfo.self, from: Data(#"{"pixelsWide":1920,"pixelsHigh":1080,"scale":2,"device":"iPad"}"#.utf8))
        precondition(!legacy.usesAppleVideoCapabilities)
        var fallback = AppleVideoFallbackPolicy()
        precondition(fallback.failHEVC(now: 10))
        precondition(!fallback.failHEVC(now: 11))
        precondition(!fallback.accepts(.hevc) && fallback.accepts(.h264))
        precondition(!fallback.expired(now: 12.9) && fallback.expired(now: 13))
        fallback.receivedH264()
        precondition(!fallback.expired(now: 20) && !fallback.accepts(.hevc))
        print("Apple video refresh, codec envelopes, config bounds and timed fallback PASS")
    }
}

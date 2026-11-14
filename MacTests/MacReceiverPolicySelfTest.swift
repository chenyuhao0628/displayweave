import Foundation

@main struct MacReceiverPolicySelfTest {
    static func main() throws {
        let hello = #"{"pixelsWide":5120,"pixelsHigh":2880,"scale":2,"device":"Mac","pv":3,"displayMaxFrameRate":60,"panel":{"pixelsWide":5120,"pixelsHigh":2880,"scale":2,"pointsWide":2560,"pointsHigh":1440},"videoCaps":[{"codec":"h264","maxWidth":4096,"maxHeight":2304,"maxFrameRate":60}]}"#
        let info = try JSONDecoder().decode(PhoneInfo.self, from: Data(hello.utf8))
        precondition(info.isMacReceiver && !info.supportsProtocolV2)
        let settings = StreamSettings(fpsMode: .fps120, codecMode: .hevc, quality: .high, transportMode: .auto, enableDebugStats: true)
        let plan = MacReceiverPolicy.plan(info: info, settings: settings)
        precondition(plan.pointsWide == 2560 && plan.pointsHigh == 1440 && plan.scale == 2)
        precondition(plan.width == 4096 && plan.height == 2304 && plan.fps == 60 && plan.codec == .h264)
        let hevc = try JSONDecoder().decode(PhoneInfo.self, from: Data(#"{"pixelsWide":5120,"pixelsHigh":2880,"scale":2,"device":"Mac","supportedCodecs":["h264","hevc"],"videoCaps":[{"codec":"hevc","maxWidth":4096,"maxHeight":2304,"maxFrameRate":60},{"codec":"h264","maxWidth":1920,"maxHeight":1080,"maxFrameRate":30}]}"#.utf8))
        let efficient = MacReceiverPolicy.plan(info: hevc, settings: settings, hardwareHEVCEncode: true)
        precondition(efficient.codec == .hevc && efficient.width <= 1920 && efficient.height <= 1080 && efficient.fps == 30)
        precondition(MacReceiverPolicy.plan(info: hevc, settings: settings, hardwareHEVCEncode: false).codec == .h264)
        var forced = settings
        forced.codecMode = .h264
        precondition(MacReceiverPolicy.plan(info: hevc, settings: forced, hardwareHEVCEncode: true).codec == .h264)
        forced.codecMode = .auto
        precondition(MacReceiverPolicy.plan(info: hevc, settings: forced, hardwareHEVCEncode: true).codec == .hevc)
        var fallback = MacCodecFallbackPolicy()
        precondition(fallback.codec(for: .hevc, isMacReceiver: true) == .hevc)
        fallback.recordFailure(.hevc)
        // A resize / fresh hello on this connection must keep H.264 after a failure.
        for _ in 0..<3 {
            let resized = MacReceiverPolicy.plan(info: hevc, settings: forced,
                sourceWidth: 1600, sourceHeight: 900, hardwareHEVCEncode: true)
            precondition(fallback.codec(for: resized.codec, isMacReceiver: true) == .h264)
        }
        precondition(fallback.codec(for: .hevc, isMacReceiver: false) == .hevc,
                     "Mac fallback must not alter the Android retry policy")
        fallback.beginConnection()
        precondition(fallback.codec(for: .hevc, isMacReceiver: true) == .hevc)
        fallback.recordFailure(.h264)
        precondition(fallback.codec(for: .hevc, isMacReceiver: true) == .hevc)
        let constrained = try JSONDecoder().decode(PhoneInfo.self, from: Data(#"{"pixelsWide":5120,"pixelsHigh":2880,"scale":2,"device":"Mac","supportedCodecs":["h264","hevc"],"maxEncodeWide":1280,"maxEncodeHigh":720,"videoCaps":[{"codec":"hevc","maxWidth":4096,"maxHeight":2304},{"codec":"h264","maxPixelsPerSecond":4}]}"#.utf8))
        let tiny = MacReceiverPolicy.plan(info: constrained, settings: settings, hardwareHEVCEncode: true)
        precondition(tiny.width * tiny.height * tiny.fps <= 4, "fallback exceeded pixel budget")
        let invalid = try JSONDecoder().decode(PhoneInfo.self, from: Data(#"{"pixelsWide":1920,"pixelsHigh":1080,"scale":1,"device":"Mac","videoCaps":[{"codec":"h264","maxWidth":0}]}"#.utf8))
        precondition(!invalid.hasValidGeometry)
        let oneX = try JSONDecoder().decode(PhoneInfo.self, from: Data(#"{"pixelsWide":1920,"pixelsHigh":1080,"scale":1,"device":"Mac"}"#.utf8))
        let plain = MacReceiverPolicy.plan(info: oneX, settings: settings)
        precondition(plain.scale == 1 && plain.pointsWide == 1920 && plain.width == 1920)
        let budget = try JSONDecoder().decode(PhoneInfo.self, from: Data(#"{"pixelsWide":3840,"pixelsHigh":2160,"scale":2,"device":"Mac","videoCaps":[{"codec":"h264","maxFrameRate":50,"maxPixelsPerSecond":248832000}]}"#.utf8))
        precondition(MacReceiverPolicy.plan(info: budget, settings: settings).fps == 30)
        let portrait = try JSONDecoder().decode(PhoneInfo.self, from: Data(#"{"pixelsWide":2160,"pixelsHigh":3840,"scale":2,"device":"Mac","videoCaps":[{"codec":"h264","maxWidth":2304,"maxHeight":4096,"maxFrameRate":60}]}"#.utf8))
        let mirrored = MacReceiverPolicy.plan(info: portrait, settings: settings, sourceWidth: 5120, sourceHeight: 2880)
        precondition(mirrored.width <= 2304 && mirrored.height <= 4096)
        precondition(!info.sameDisplayConfiguration(as: portrait))
        let exactConfig = StreamConfigMessage(codec: .h264, fps: 24, width: 1920, height: 1080,
            bitrate: 8000000, transport: "lan", exactFrameRate: true)
        let object = try JSONSerialization.jsonObject(with: Data(exactConfig.json.utf8)) as! [String: Any]
        precondition(object["fps"] as? Int == 24 && object["framesPerSecond"] as? Int == 24)
        var decoder = ReceiverFrameDecoder(maxFrameBytes: 10)
        let a = ReceiverFrameDecoder.frame(Data([1,2,3]))
        let partial = try decoder.append(a.prefix(2))
        precondition(partial.isEmpty)
        let frames = try decoder.append(a.dropFirst(2) + ReceiverFrameDecoder.frame(Data([4])))
        precondition(frames == [Data([1,2,3]), Data([4])])
        for size: UInt32 in [0, 11, UInt32.max] {
            var bad = ReceiverFrameDecoder(maxFrameBytes: 10)
            var value = size.bigEndian
            do { _ = try bad.append(Data(bytes: &value, count: 4)); fatalError("invalid size accepted") }
            catch ReceiverFrameDecoder.Failure.invalidLength { }
        }
        // C1: macOS 26.1 >=200 cm² (20,000 mm²) virtual display physical size floor & clamping
        let mobileDefault = try JSONDecoder().decode(PhoneInfo.self, from: Data(#"{"pixelsWide":2400,"pixelsHigh":1080,"scale":2,"device":"Android"}"#.utf8))
        let landscapeMm = VirtualDisplayPhysicalSizePolicy.millimeters(for: mobileDefault, pointsWide: 1200, pointsHigh: 540)
        precondition(landscapeMm.width == 208 && landscapeMm.height == 96 && landscapeMm.width * landscapeMm.height >= 19_968,
                     "default landscape mobile virtual display must be 208x96 mm (~200 cm²)")
        let portraitMm = VirtualDisplayPhysicalSizePolicy.millimeters(for: mobileDefault, pointsWide: 540, pointsHigh: 1200)
        precondition(portraitMm.width == 96 && portraitMm.height == 208,
                     "default portrait mobile virtual display must be 96x208 mm (~200 cm²)")
        let tinyPhone = try JSONDecoder().decode(PhoneInfo.self, from: Data(#"{"pixelsWide":2556,"pixelsHigh":1179,"scale":3,"device":"iPhone","panel":{"millimetersWide":147,"millimetersHigh":68}}"#.utf8))
        let scaledPhoneMm = VirtualDisplayPhysicalSizePolicy.millimeters(for: tinyPhone, pointsWide: 852, pointsHigh: 393)
        precondition(scaledPhoneMm.width * scaledPhoneMm.height >= 20_000,
                     "small mobile panel mm must scale proportionally above 200 cm²")
        precondition(abs((scaledPhoneMm.width / scaledPhoneMm.height) - (147.0 / 68.0)) < 0.01,
                     "proportional scaling must preserve physical aspect ratio")
        let hugePanel = VirtualDisplayPhysicalSizePolicy.clampedMillimeters(width: 4000, height: 2250)!
        precondition(hugePanel.width <= 2000 && hugePanel.height <= 2000 && hugePanel.width * hugePanel.height >= 20_000,
                     "oversized physical dimensions must clamp to <= 2000 mm")

        // H.264 4K fallback clamp
        let clampedFallback = MacReceiverPolicy.clampedH264Dimensions(width: 5120, height: 2880)
        precondition(clampedFallback.width == 4096 && clampedFallback.height == 2304,
                     "runtime HEVC-to-H.264 fallback helper must clamp 5120x2880 to 4096x2304")
        let clampedPortraitFallback = MacReceiverPolicy.clampedH264Dimensions(width: 2880, height: 5120)
        precondition(clampedPortraitFallback.width == 2304 && clampedPortraitFallback.height == 4096,
                     "runtime HEVC-to-H.264 fallback helper must clamp portrait 2880x5120 to 2304x4096")

        print("Mac receiver geometry, negotiation and framing passed")
    }
}

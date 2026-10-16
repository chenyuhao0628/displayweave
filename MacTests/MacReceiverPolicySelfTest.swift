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
        print("Mac receiver geometry, negotiation and framing passed")
    }
}

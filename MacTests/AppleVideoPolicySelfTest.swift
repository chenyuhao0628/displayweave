import Foundation

@main enum AppleVideoPolicySelfTest {
    static func main() throws {
        nativeHighRefreshAdmission()
        try nativeHighRefreshPlans()
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
        var motion = settings
        motion.priority = .frameRate
        let fast = MacReceiverPolicy.plan(info: info, settings: motion,
            sourceWidth: 3840, sourceHeight: 2160, hardwareHEVCEncode: true)
        precondition(fast.fps == 120 && fast.width < 3840 && fast.width * fast.height * fast.fps <= 566231040,
                     "frame-rate priority fits raster to the receiver throughput envelope")
        motion.fpsMode = .fps30
        let office = MacReceiverPolicy.plan(info: info, settings: motion,
            sourceWidth: 3840, sourceHeight: 2160, hardwareHEVCEncode: true)
        precondition(office.fps == 30 && office.width == 3840, "30 fps retains native detail when supported")
        let alternatives = #"{"pixelsWide":3840,"pixelsHigh":2160,"scale":1,"device":"Mac","displayMaxFrameRate":120,"videoCaps":[{"codec":"h264","maxWidth":3840,"maxHeight":2160,"maxFrameRate":30},{"codec":"h264","maxWidth":2560,"maxHeight":1440,"maxFrameRate":120}]}"#
        let alternativeInfo = try JSONDecoder().decode(PhoneInfo.self, from: Data(alternatives.utf8))
        let detailed = MacReceiverPolicy.plan(info: alternativeInfo, settings: settings)
        precondition(detailed.width == 3840 && detailed.fps == 30,
                     "resolution priority compares raster before aggregate pixel throughput")
        motion.fpsMode = .auto
        let fasterInfo = try JSONDecoder().decode(PhoneInfo.self,
            from: Data(alternatives.replacingOccurrences(of: "\"maxFrameRate\":30", with: "\"maxFrameRate\":60").utf8))
        let faster = MacReceiverPolicy.plan(info: fasterInfo, settings: motion)
        precondition(faster.width == 2560 && faster.fps == 120,
                     "frame-rate priority compares FPS before aggregate pixel throughput")
        let legacy = try JSONDecoder().decode(PhoneInfo.self, from: Data(#"{"pixelsWide":1920,"pixelsHigh":1080,"scale":2,"device":"iPad"}"#.utf8))
        precondition(!legacy.usesAppleVideoCapabilities)
        // OpenDisplay v1.25.0 / b9eec1f, Shared/StreamReceiver.swift::sendHello.
        // Extra pv/cursor fields are additive; Apple must not enter Android V2.
        let upstream = #"{"pixelsWide":1920,"pixelsHigh":1080,"scale":1,"device":"Mac","id":"upstream-peer","pv":3,"displayMaxFrameRate":60,"panel":{"pixelsWide":1920,"pixelsHigh":1080,"scale":1},"videoCaps":[{"codec":"h264","maxWidth":1920,"maxHeight":1080,"maxFrameRate":60}],"cursorPort":9001}"#
        let upstreamInfo = try JSONDecoder().decode(PhoneInfo.self, from: Data(upstream.utf8))
        precondition(upstreamInfo.hasValidGeometry && !upstreamInfo.supportsProtocolV2)
        let upstreamPlan = MacReceiverPolicy.plan(info: upstreamInfo, settings: settings, hardwareHEVCEncode: true)
        precondition(upstreamPlan.codec == .h264 && upstreamPlan.fps <= 60)
        let upstreamConfig: [String: Any] = ["type": "streamConfig", "codec": "h264", "width": 1920, "height": 1080, "framesPerSecond": 30]
        precondition(AppleVideoConfiguration(upstreamConfig, maxWidth: 1920, maxHeight: 1080, maxFps: 60)?.fps == 30)
        // Early pre-version/pre-install-ID iOS remains H.264; no invented V2 capability.
        precondition(legacy.id == nil && legacy.hasValidGeometry && !legacy.supportsProtocolV2)
        var fallback = AppleVideoFallbackPolicy()
        precondition(fallback.failHEVC(now: 10))
        precondition(!fallback.failHEVC(now: 11))
        precondition(!fallback.accepts(.hevc) && fallback.accepts(.h264))
        precondition(!fallback.expired(now: 12.9) && fallback.expired(now: 13))
        fallback.receivedH264()
        precondition(!fallback.expired(now: 20) && !fallback.accepts(.hevc))
        print("Apple video refresh, codec envelopes, config bounds and timed fallback PASS")
    }

    private static func nativeHighRefreshAdmission() {
        let native = AppleVideoPolicy.nativeHighRefreshEnvelope(width: 2752, height: 2064, maxFps: 120)!
        let object: [String: Any] = ["codec": "hevc", "width": 2752, "height": 2064, "fps": 120]
        precondition(AppleVideoConfiguration(object, maxWidth: 4096, maxHeight: 2304, maxFps: 120) == nil,
                     "the conservative default must not silently opt in")
        let accepted = AppleVideoConfiguration(object, maxWidth: 4096, maxHeight: 2304, maxFps: 120,
                                              nativeEnvelope: native)
        precondition(accepted?.width == 2752 && accepted?.height == 2064 && accepted?.fps == 120
                     && accepted?.codec == .hevc, "the explicit native envelope preserves all native pixels")
        let wide: [String: Any] = ["codec": "hevc", "width": 4096, "height": 2304, "fps": 72]
        precondition(AppleVideoConfiguration(wide, maxWidth: 4096, maxHeight: 2304, maxFps: 120,
                                            nativeEnvelope: native) == nil,
                     "a point below the extra pixel budget must still fit the complete native rectangle")
        precondition(AppleVideoConfiguration(object, maxWidth: 4096, maxHeight: 2304, maxFps: 60,
                                            nativeEnvelope: native) == nil, "the screen ceiling still applies")
        let slower = object.merging(["fps": 90]) { _, value in value }
        precondition(AppleVideoConfiguration(slower, maxWidth: 4096, maxHeight: 2304, maxFps: 120)?.fps == 90,
                     "native 90 fps remains available without the trial")
        let portrait = AppleVideoPolicy.nativeHighRefreshEnvelope(width: 2064, height: 2752, maxFps: 120)!
        let rotated = object.merging(["width": 2064, "height": 2752]) { _, value in value }
        let acceptedPortrait = AppleVideoConfiguration(rotated, maxWidth: 2304, maxHeight: 4096, maxFps: 120,
                                                      nativeEnvelope: portrait)
        precondition(acceptedPortrait?.width == 2064 && acceptedPortrait?.height == 2752
                     && acceptedPortrait?.fps == 120, "native admission follows the announced orientation")
        precondition(AppleVideoConfiguration(rotated, maxWidth: 2304, maxHeight: 4096, maxFps: 120,
                                            nativeEnvelope: native) == nil, "alternative rectangles cannot be combined")
        let swappedFromPortrait = AppleVideoPolicy.nativeHighRefreshEnvelope(
            width: portrait.height, height: portrait.width, maxFps: portrait.fps)
        let swappedAccepted = AppleVideoConfiguration(object, maxWidth: 2304, maxHeight: 4096, maxFps: 120,
                                                      nativeEnvelope: portrait)
            ?? AppleVideoConfiguration(object, maxWidth: 4096, maxHeight: 2304, maxFps: 120,
                                       nativeEnvelope: swappedFromPortrait)
        precondition(swappedAccepted?.width == 2752 && swappedAccepted?.height == 2064 && swappedAccepted?.fps == 120,
                     "PhoneReceiver.configureVideo orientation-swap fallback must admit rotated native high-refresh config")
        precondition(AppleVideoPolicy.nativeHighRefreshEnvelope(width: Int.max, height: 2064, maxFps: 120) == nil)
        precondition(AppleVideoPolicy.nativeHighRefreshEnvelope(width: 2751, height: 2064, maxFps: 120) == nil)
        precondition(AppleVideoPolicy.nativeHighRefreshEnvelope(width: 2752, height: 2064, maxFps: 60) == nil)
        precondition(AppleVideoPolicy.nativeHighRefreshEnvelope(width: 2420, height: 1668, maxFps: 120) == nil)
    }

    private static func nativeHighRefreshPlans() throws {
        let native = AppleVideoPolicy.nativeHighRefreshEnvelope(width: 2752, height: 2064, maxFps: 120)!
        let legacyCaps = ["h264", "hevc"].map {
            ["codec": $0, "maxWidth": 4096, "maxHeight": 2304, "maxFrameRate": 120,
             "maxPixelsPerSecond": AppleVideoPolicy.maxPixelsPerSecond] as [String: Any]
        }
        func info(_ caps: [[String: Any]]) throws -> PhoneInfo {
            let hello: [String: Any] = ["pixelsWide": 2752, "pixelsHigh": 2064, "scale": 2, "device": "iPad",
                "capabilities": [AppleVideoPolicy.capability], "supportedCodecs": ["h264", "hevc"],
                "displayMaxFrameRate": 120, "videoCaps": caps]
            return try JSONDecoder().decode(PhoneInfo.self, from: JSONSerialization.data(withJSONObject: hello))
        }
        var settings = StreamSettings(fpsMode: .auto, codecMode: .auto, quality: .high,
                                      transportMode: .auto, enableDebugStats: true)
        settings.priority = .frameRate
        let conservative = MacReceiverPolicy.plan(info: try info(legacyCaps), settings: settings, hardwareHEVCEncode: true)
        precondition(conservative.fps == 120 && conservative.width < 2752 && conservative.height < 2064)
        let enabled = try info(legacyCaps + ["h264", "hevc"].map { native.capability(codec: $0) })
        let hevc = MacReceiverPolicy.plan(info: enabled, settings: settings, hardwareHEVCEncode: true)
        precondition(hevc.width == 2752 && hevc.height == 2064 && hevc.fps == 120 && hevc.codec == .hevc)
        precondition(hevc.pointsWide == 1376 && hevc.pointsHigh == 1032 && hevc.scale == 2,
                     "native encoded pixels must not change the HiDPI desktop layout")
        settings.codecMode = .h264
        let h264 = MacReceiverPolicy.plan(info: enabled, settings: settings, hardwareHEVCEncode: true)
        precondition(h264.width == hevc.width && h264.height == hevc.height
                     && h264.fps == hevc.fps && h264.codec == .h264, "same-raster fallback stays valid")
        settings.codecMode = .auto
        let hevcOnly = try info(legacyCaps + [native.capability(codec: "hevc")])
        let safe = MacReceiverPolicy.plan(info: hevcOnly, settings: settings, hardwareHEVCEncode: true)
        precondition(safe.fps == 120 && safe.width < 2752 && safe.height < 2064,
                     "an HEVC-only native offer must not bypass the conservative H.264 fallback")
    }
}

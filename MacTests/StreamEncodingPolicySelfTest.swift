import Foundation

func assertEqual(_ expected: Int, _ actual: Int, _ message: String) {
    if expected != actual {
        fatalError("\(message): expected \(expected), got \(actual)")
    }
}

func assertEqual(_ expected: StreamCodec, _ actual: StreamCodec, _ message: String) {
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
struct StreamEncodingPolicySelfTest {
    static func main() {
        assertEqual(.h264,
                    StreamEncodingPolicy.selectedCodec(
                        supportedCodecs: ["h264", "hevc"],
                        preferredCodec: "h264"),
                    "Android preferred codec is respected when supported")
        assertEqual(.hevc,
                    StreamEncodingPolicy.selectedCodec(
                        supportedCodecs: ["h264", "hevc"],
                        preferredCodec: nil),
                    "HEVC is selected by default whenever the Android side supports it")
        assertEqual(.h264,
                    StreamEncodingPolicy.selectedCodec(
                        supportedCodecs: ["h264"],
                        preferredCodec: "hevc"),
                    "H.264 is selected when HEVC is unsupported")

        let hevc1080p120 = StreamEncodingPolicy.bitrate(
            width: 1920, height: 1080, fps: 120, codec: .hevc, quality: .high)
        assertTrue((20_000_000...35_000_000).contains(hevc1080p120),
                   "1080p120 HEVC bitrate should be in the requested initial range")

        let hevc1600p120 = StreamEncodingPolicy.bitrate(
            width: 2560, height: 1600, fps: 120, codec: .hevc, quality: .high)
        assertTrue((50_000_000...80_000_000).contains(hevc1600p120),
                   "1600p120 HEVC bitrate should be in the requested initial range")

        let h2641080p60 = StreamEncodingPolicy.bitrate(
            width: 1920, height: 1080, fps: 60, codec: .h264, quality: .high)
        assertTrue((12_000_000...20_000_000).contains(h2641080p60),
                   "1080p60 H.264 bitrate should be in the requested initial range")

        let lowBitrate = StreamEncodingPolicy.bitrate(
            width: 1920, height: 1080, fps: 120, codec: .hevc, quality: .low)
        let gamingBitrate = StreamEncodingPolicy.bitrate(
            width: 1920, height: 1080, fps: 120, codec: .hevc, quality: .gaming)
        assertTrue(lowBitrate < gamingBitrate && gamingBitrate < hevc1080p120,
                   "quality mode should tune bitrate without changing codec/fps negotiation")

        assertEqual(12_000_000,
                    StreamEncodingPolicy.bitrateBounds(codec: .hevc, transport: .wifi).lowerBound,
                    "HEVC WiFi lower bound")
        assertEqual(100_000_000,
                    StreamEncodingPolicy.bitrateBounds(codec: .hevc, transport: .wifi).upperBound,
                    "HEVC WiFi upper bound")
        assertEqual(160_000_000,
                    StreamEncodingPolicy.bitrateBounds(codec: .hevc, transport: .usb).upperBound,
                    "HEVC USB upper bound")
        assertEqual(60_000_000,
                    StreamEncodingPolicy.bitrateBounds(codec: .h264, transport: .wifi).upperBound,
                    "H.264 WiFi upper bound")
        assertEqual(100_000_000,
                    StreamEncodingPolicy.bitrateBounds(codec: .h264, transport: .usb).upperBound,
                    "H.264 USB upper bound")
        assertEqual(60_000_000,
                    StreamEncodingPolicy.selectedBitrate(
                        mode: .manual, preset: .mbps80, automatic: 20_000_000,
                        codec: .h264, transport: .wifi),
                    "manual values clamp to codec/transport bounds")
        assertEqual(200_000_000,
                    StreamEncodingPolicy.selectedBitrate(
                        mode: .benchmark, preset: .mbps200, automatic: 20_000_000,
                        codec: .hevc, transport: .usb),
                    "benchmark mode alone permits 200 Mbps")

        assertEqual(120,
                    StreamEncodingPolicy.keyframeInterval(fps: 120),
                    "keyframe interval tracks one second of frames")
        assertEqual(120,
                    StreamEncodingPolicy.frameDurationTimescale(fps: 120),
                    "frame duration timescale tracks final fps")

        let pingJson = StreamDebugStats(
            droppedFramesMac: 2,
            queueDepthMac: 3,
            captureFps: 120,
            requestedFps: 120,
            actualVirtualDisplayRefreshRate: 120,
            encodedFps: 119,
            sentFps: 118,
            averageFrameSize: 425_000,
            encodeLatencyMs: 4.5,
            bitrate: 60_000_000,
            inputP50Ms: 7,
            inputP95Ms: 13
        ).pingJson(nowMs: 1234.5)
        assertTrue(pingJson.contains("\"type\":\"ping\""),
                   "debug stats ping should stay on the existing ping control message")
        assertTrue(pingJson.contains("\"droppedFramesMac\":2"),
                   "debug stats ping should expose droppedFramesMac")
        assertTrue(pingJson.contains("\"queueDepthMac\":3"),
                   "debug stats ping should expose queueDepthMac")
        assertTrue(pingJson.contains("\"encodedFps\":119"),
                   "debug stats ping should expose encodedFps")
        assertTrue(pingJson.contains("\"sentFps\":118"),
                   "debug stats ping should expose sentFps")
        assertTrue(pingJson.contains("\"averageFrameSize\":425000"),
                   "debug stats ping should expose averageFrameSize")
        assertTrue(pingJson.contains("\"encodeLatencyMs\":4.5"),
                   "debug stats ping should expose encodeLatencyMs")

        let fallbackConfig = StreamConfigMessage(
            codec: .h264,
            fps: 120,
            width: 2560,
            height: 1600,
            bitrate: 30_000_000,
            transport: "wifi"
        ).json
        assertTrue(fallbackConfig.contains("\"type\":\"streamConfig\""),
                   "fallback stream config should use the existing streamConfig control message")
        assertTrue(fallbackConfig.contains("\"codec\":\"h264\""),
                   "fallback stream config should announce H.264")
        assertTrue(fallbackConfig.contains("\"fps\":120"),
                   "fallback stream config should preserve the negotiated fps")
        assertTrue(fallbackConfig.contains("\"profile\":\"high\""),
                   "fallback stream config should announce the H.264 profile")
        assertTrue(!fallbackConfig.contains("sessionEpoch"),
                   "legacy stream config must not gain protocol-v2 fields")
        assertTrue(!fallbackConfig.contains("maxFrameBytes"),
                   "legacy stream config must not negotiate a larger frame")

        var identity = StreamProtocolIdentity()
        identity.beginConnection()
        let firstConfig = identity.beginConfiguration()
        let negotiatedConfig = StreamConfigMessage(
            codec: .hevc, fps: 120, width: 2560, height: 1600,
            bitrate: 60_000_000, transport: "wifi", identity: firstConfig,
            maxFrameBytes: 8 * 1_024 * 1_024
        ).json
        assertTrue(negotiatedConfig.contains("\"protocolVersion\":2"),
                   "negotiated stream config declares protocol v2")
        assertTrue(negotiatedConfig.contains("\"sessionEpoch\":1"),
                   "first connection starts epoch one")
        assertTrue(negotiatedConfig.contains("\"configVersion\":1"),
                   "first configuration starts version one")
        assertTrue(negotiatedConfig.contains("\"maxFrameBytes\":8388608"),
                   "negotiated stream config echoes the bounded receiver limit")
        assertTrue(FrameSizePolicy.permits(
            payloadBytes: 8 * 1_024 * 1_024,
            negotiatedMaxBytes: 8 * 1_024 * 1_024),
            "a frame at the negotiated V2 limit is allowed")
        assertTrue(!FrameSizePolicy.permits(
            payloadBytes: 8 * 1_024 * 1_024 + 1,
            negotiatedMaxBytes: 8 * 1_024 * 1_024),
            "a frame above the negotiated V2 limit is rejected before write")
        assertTrue(!FrameSizePolicy.permits(
            payloadBytes: 0,
            negotiatedMaxBytes: 8 * 1_024 * 1_024),
            "a zero-length payload is never a valid frame")
        assertTrue(FrameSizePolicy.permits(
            payloadBytes: FrameSizePolicy.legacyMaxBytes + 1,
            negotiatedMaxBytes: nil),
            "legacy send behavior stays unnegotiated and unchanged")
        let frameOne = identity.nextFrame()
        let frameTwo = identity.nextFrame()
        assertEqual(1, Int(frameOne.frameSequence), "first frame sequence")
        assertEqual(2, Int(frameTwo.frameSequence), "frame sequence increments")
        identity.beginConnection()
        let nextConfig = identity.beginConfiguration()
        assertEqual(2, Int(nextConfig.sessionEpoch), "reconnect increments session epoch")
        assertEqual(1, Int(nextConfig.configVersion), "new session resets config version")
        var replacementSenderIdentity = StreamProtocolIdentity()
        replacementSenderIdentity.beginConnection()
        assertTrue(replacementSenderIdentity.sessionEpoch > nextConfig.sessionEpoch,
                   "a replacement sender in the same process must receive a newer epoch")

        let prefix = VideoTelemetryPrefix.json(
            captureMs: 10, sendMs: 20, identity: frameTwo)
        assertTrue(prefix.contains("\"se\":1,\"cv\":1,\"fs\":2"),
                   "negotiated frame prefix carries epoch/version/sequence")
        assertTrue(VideoTelemetryPrefix.json(captureMs: 10, sendMs: 20, identity: nil)
            == "{\"cap\":10,\"snd\":20}",
                   "legacy telemetry prefix remains byte-for-byte unchanged")

        var handshake = ReceiverProtocolHandshake()
        handshake.begin(firstConfig)
        assertTrue(handshake.receive(type: "streamConfigAck", identity: firstConfig),
                   "matching streamConfig ack advances the handshake")
        assertTrue(handshake.phase == .awaitingDecoderReady,
                   "ack waits for decoder ready")
        assertTrue(!handshake.receive(type: "decoderReady", identity: nextConfig),
                   "stale epoch/config progress is ignored")
        assertTrue(handshake.receive(type: "decoderReady", identity: firstConfig),
                   "matching decoder ready advances the handshake")
        assertTrue(handshake.phase == .awaitingFirstFrame,
                   "decoder ready waits for first rendered frame")
        assertTrue(!handshake.receive(type: "firstFrameRendered", identity: firstConfig),
                   "first-frame progress requires a positive frame sequence")
        assertTrue(handshake.receive(type: "firstFrameRendered", identity: frameOne),
                   "matching first frame completes the handshake")
        assertTrue(handshake.phase == .streaming,
                   "first rendered frame is the only streaming proof")

        handshake.begin(firstConfig)
        assertTrue(handshake.timeoutAction() == .retry,
                   "first negotiated timeout requests a finite retry")
        assertTrue(handshake.timeoutAction() == .retry,
                   "second negotiated timeout requests the final retry")
        assertTrue(handshake.timeoutAction() == .fail,
                   "retry budget exhaustion fails instead of looping forever")

        var failureBudget = ReceiverProtocolFailureBudget(maxReconnects: 1)
        assertTrue(failureBudget.failureAction() == .reconnect,
                   "one failed handshake may reconnect once")
        assertTrue(failureBudget.failureAction() == .endSession,
                   "repeated failed handshakes end the session")
        failureBudget.markStreaming()
        assertTrue(failureBudget.failureAction() == .reconnect,
                   "a proven streaming session resets the cross-connection budget")

        assertTrue(
            ReceiverDecoderRecoveryPolicy.actions(
                negotiatedV2: true,
                streamConfigRequired: true
            ) == [.resendStreamConfig, .forceKeyframe],
            "a negotiated decoder rebuild must create a fresh config version before keyframe"
        )
        assertTrue(
            ReceiverDecoderRecoveryPolicy.actions(
                negotiatedV2: false,
                streamConfigRequired: true
            ) == [.forceKeyframe],
            "legacy receiver recovery must preserve the existing keyframe-only behavior"
        )

        print("StreamEncodingPolicySelfTest PASS")
    }
}

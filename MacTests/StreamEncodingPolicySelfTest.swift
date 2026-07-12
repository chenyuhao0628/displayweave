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

        print("StreamEncodingPolicySelfTest PASS")
    }
}

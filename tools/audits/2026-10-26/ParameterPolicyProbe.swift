// Calls production policies. This observes current behavior, not fixed behavior.
import Foundation

@main struct ParameterPolicyProbe {
    static func main() throws {
        let lan = AdaptiveBitrateController(initialBitrate: 40_000_000,
                                            bounds: 8_000_000...100_000_000)
        let usb = AdaptiveBitrateController(initialBitrate: 40_000_000,
                                            bounds: 8_000_000...100_000_000)
        var decreases = 0
        for tick in 0..<10 {
            var metrics = AdaptiveBitrateMetrics(timestamp: Double(tick * 2),
                pendingSends: 0, encodedFps: 60, sentFps: 60, rttMs: 2,
                frameAgeP95Ms: 8, macDrops: 1, androidDrops: 0,
                androidCongestionDrops: 0, androidQueueDepth: 0, transport: .wifi)
            if let decision = lan.evaluate(metrics, mode: .auto),
               decision.newBitrate < decision.previousBitrate {
                precondition(decision.trigger == "mac-drops")
                decreases += 1
            }
            metrics.transport = .usb
            _ = usb.evaluate(metrics, mode: .auto)
        }
        print("ABR: empty send/receiver queues, sent == encoded, stable RTT/age, one Mac drop/window: LAN 40 -> \(lan.currentBitrate / 1_000_000) Mbps (\(decreases) decreases); USB \(usb.currentBitrate) bps")
        precondition(lan.currentBitrate == 8_000_000 && usb.currentBitrate >= 40_000_000)

        let local = AdaptiveBitrateController(initialBitrate: 40_000_000,
            bounds: 8_000_000...100_000_000, localRecovery: true)
        func localSample(_ time: Double, pending: Int, age: Double = 2) -> LocalCongestionMetrics {
            LocalCongestionMetrics(timestamp: time, pendingSends: pending, queueBudget: 3,
                oldestPendingSendAgeMs: age, encodedFps: 60, sentFps: 60,
                sendCompletionDelayMs: 2)
        }
        _ = local.evaluateLocal(localSample(0, pending: 3), mode: .auto)
        _ = local.evaluateLocal(localSample(0.2, pending: 3), mode: .auto)
        let decreased = local.currentBitrate
        for tick in 2...301 {
            _ = local.evaluateLocal(localSample(Double(tick) * 0.2, pending: 1), mode: .auto)
        }
        precondition(local.currentBitrate == decreased)
        print("Local recovery: 60 seconds at pending=1/3, constant oldest age=2ms, sent == encoded: stays at \(decreased) bps")
        for tick in 302...333 {
            _ = local.evaluateLocal(localSample(Double(tick) * 0.2, pending: 0, age: 0), mode: .auto)
        }
        precondition(local.currentBitrate > decreased)
        print("Local recovery: fully drained samples allow recovery -> \(local.currentBitrate) bps")

        let json = #"{"pixelsWide":3840,"pixelsHigh":2160,"scale":2,"device":"Mac","id":"audit-fixture","displayMaxFrameRate":120,"supportedCodecs":["h264","hevc"],"videoCaps":[{"codec":"h264","maxWidth":4096,"maxHeight":2304,"maxFrameRate":120,"maxPixelsPerSecond":566231040},{"codec":"hevc","maxWidth":4096,"maxHeight":2304,"maxFrameRate":120,"maxPixelsPerSecond":566231040}]}"#
        let hello = try JSONDecoder().decode(PhoneInfo.self, from: Data(json.utf8))
        var settings = StreamSettings(fpsMode: .fps120, codecMode: .auto,
            quality: .high, transportMode: .auto, enableDebugStats: true)
        let high = MacReceiverPolicy.plan(info: hello, settings: settings, hardwareHEVCEncode: true)
        settings.quality = .balanced
        let balanced = MacReceiverPolicy.plan(info: hello, settings: settings, hardwareHEVCEncode: true)
        print("Apple 4K/120 request: high = \(high.width)x\(high.height)@\(high.fps); balanced = \(balanced.width)x\(balanced.height)@\(balanced.fps)")
        precondition(high.fps == 60 && balanced.fps == 120)

        let shownPresets = StreamEncodingPolicy.availablePresets(mode: .manual, codec: .hevc, transport: .usb)
        let actualLAN = StreamEncodingPolicy.selectedBitrate(mode: .manual, preset: .mbps160,
            automatic: 0, codec: .hevc, transport: .wifi)
        let actualH264 = StreamEncodingPolicy.selectedBitrate(mode: .manual, preset: .mbps160,
            automatic: 0, codec: .h264, transport: .usb)
        precondition(shownPresets.contains(.mbps160) && actualLAN == 100_000_000 && actualH264 == 100_000_000)
        print("Manual UI under Auto codec/transport offers 160 Mbps; actual LAN HEVC = \(actualLAN / 1_000_000), USB H.264 = \(actualH264 / 1_000_000) Mbps")

        let desktop = DesktopResolutionPolicy.geometry(.native,
            nativeWidth: 1920, nativeHeight: 1200, backingScale: 2)
        let doubledScale = DesktopResolutionPolicy.raster(desktop, qualityScale: 0.75,
            maxWidth: 1920, maxHeight: 1200)
        print("Android 2560x1600 at receiver 75% + sender 75%: \(doubledScale.width)x\(doubledScale.height), 56.25% per axis / 31.64% pixels")
        precondition(doubledScale.width == 1440 && doubledScale.height == 900)

        let ping = StreamDebugStats(droppedFramesMac: 9, queueDepthMac: 2,
            pendingEncodesMac: 0, totalPendingWorkMac: 2, pendingEncodePeak: 2,
            captureFps: 60, requestedFps: 60, actualVirtualDisplayRefreshRate: 60,
            encodedFps: 60, sentFps: 60, averageFrameSize: 10000, encodeLatencyMs: 4,
            bitrate: 40000000, inputP50Ms: 0, inputP95Ms: 0).pingJson(nowMs: 0)
        let object = try JSONSerialization.jsonObject(with: Data(ping.utf8)) as! [String: Any]
        precondition(object["droppedFramesMac"] as? Int == 9 && object["queueDepthMac"] as? Int == 2)
        precondition(object["drops"] == nil && object["pending"] == nil)
        print("iOS telemetry contract: sender emits droppedFramesMac=9/queueDepthMac=2; consumer keys drops/pending are absent (fresh state stays 0/0)")
    }
}

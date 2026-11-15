import Foundation
import Darwin
import AVFoundation
import VideoToolbox

private final class ReceiverLogProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var recorded = false
    func accept(_ line: String) {
        if line.hasPrefix("MAC-RECEIVER-STATS ") { lock.withLock { recorded = true } }
    }
    var observed: Bool { lock.withLock { recorded } }
}

@main struct MacReceiverNetworkSelfTest {
    @MainActor static func waitFor(_ description: String, _ condition: () -> Bool) async throws {
        for _ in 0..<100 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(50))
        }
        throw ReceiverTestFailure(message: "timeout: \(description)")
    }

    @MainActor static func main() async throws {
        // Optional local visual smoke producer. Connects only to loopback and
        // sends synthetic color bars, never captures the user's desktop.
        if let index = CommandLine.arguments.firstIndex(of: "--smoke-port"),
           CommandLine.arguments.count > index + 1, let port = UInt16(CommandLine.arguments[index + 1]) {
            try await Task.detached {
                let peer = try ReceiverTestPeer(port: port)
                _ = try peer.hello()
                let config = try JSONSerialization.data(withJSONObject: ["type":"streamConfig", "codec":"h264", "width":64, "height":64, "fps":30])
                try peer.write(ReceiverFrameDecoder.frame(config))
                let frame = ReceiverFrameDecoder.frame(try receiverTestH264Frame())
                for _ in 0..<1800 {
                    try peer.write(frame)
                    try await Task.sleep(for: .milliseconds(33))
                }
            }.value
            return
        }
        let logProbe = ReceiverLogProbe()
        let receiver = StreamReceiver(diagnostic: { logProbe.accept($0) }, securityProvider: { .legacy })
        receiver.configure(panel: PanelAnnouncement(pixelsWide: 1920, pixelsHigh: 1080, scale: 1,
                           millimetersWide: 530, millimetersHigh: 300),
                           name: "Test", maxFps: 120)
        receiver.start(port: 0, advertiseService: false)
        try await waitFor("listen") { receiver.listeningPort != 0 }
        let port = receiver.listeningPort
        let first = try await Task.detached { () -> ReceiverTestPeer in
            let peer = try ReceiverTestPeer(port: port)
            let hello = try peer.hello()
            precondition(hello["device"] as? String == "Mac")
            precondition(hello["maxFps"] as? Int == 120)
            let panel = hello["panel"] as? [String: Any]
            precondition(panel?["millimetersWide"] as? Int == 530 && panel?["millimetersHigh"] as? Int == 300)
            precondition((hello["supportedCodecs"] as? [String])?.contains("h264") == true)
            precondition(hello["protocolVersion"] == nil && hello["power"] == nil && hello["cursorPort"] == nil)
            return peer
        }.value
        try await waitFor("connected") { receiver.connected }
        try await Task.detached {
            for _ in 0..<8 {
                let message = try first.hello()
                if message["type"] as? String == "macReceiverStats" {
                    precondition(message["videoEnqueuedFps"] != nil && message["cursorDispatchMaxMs"] != nil
                        && message["backpressureToleratedFrames"] != nil)
                    return
                }
            }
            throw ReceiverTestFailure(message: "receiver diagnostics were not sent to sender")
        }.value
        try await waitFor("receiver diagnostics log") { logProbe.observed }
        // Simulate a busy UI while cursor controls continue arriving. When the
        // UI becomes available it should draw the newest point, not replay a
        // trail of obsolete points. Pong fences processing on the receive queue.
        var cursorUpdates = 0
        var cursorX = -1.0
        receiver.onCursor = { x, _, _ in cursorUpdates += 1; cursorX = x }
        let cursorFence = DispatchSemaphore(value: 0)
        let cursorBurst = Task.detached {
            defer { cursorFence.signal() }
            var batch = Data()
            let badNegativeSeq = try JSONSerialization.data(withJSONObject:
                ["type": "cursor", "x": 0.25, "y": 0.5, "v": 1, "s": -1])
            let badOutOfRangeCoord = try JSONSerialization.data(withJSONObject:
                ["type": "cursor", "x": 1.5, "y": 0.5, "v": 1, "s": 9999])
            batch.append(ReceiverFrameDecoder.frame(badNegativeSeq))
            batch.append(ReceiverFrameDecoder.frame(badOutOfRangeCoord))
            for index in 1...240 {
                let cursor = try JSONSerialization.data(withJSONObject:
                    ["type": "cursor", "x": Double(index) / 240, "y": 0.5, "v": 1, "s": index])
                batch.append(ReceiverFrameDecoder.frame(cursor))
            }
            batch.append(ReceiverFrameDecoder.frame(try JSONSerialization.data(withJSONObject:
                ["type": "ping", "t": 424242])))
            try first.write(batch)
            for _ in 0..<8 {
                let reply = try first.hello()
                if reply["type"] as? String == "pong", reply["t"] as? Int == 424242 { return }
            }
            throw ReceiverTestFailure(message: "cursor burst fence missing")
        }
        precondition(cursorFence.wait(timeout: .now() + 5) == .success, "cursor processing stalled with busy main thread")
        try await cursorBurst.value
        try await waitFor("newest cursor") { cursorX == 1 }
        precondition(cursorUpdates == 1, "busy main thread replayed \(cursorUpdates) stale cursor positions")
        receiver.onCursor = nil
        try await Task.detached {
            let busy = try ReceiverTestPeer(port: port)
            precondition(busy.isClosed(), "second sender displaced active sender")
        }.value
        let video = try await Task.detached { try receiverTestH264Frame() }.value
        let config = try JSONSerialization.data(withJSONObject: ["type":"streamConfig", "codec":"h264", "width":64, "height":64, "framesPerSecond":120])
        let welcome = try JSONSerialization.data(withJSONObject: ["type":"welcome", "pv":3, "minSupportedPeer":1])
        let stream = ReceiverFrameDecoder.frame(welcome) + ReceiverFrameDecoder.frame(config) + ReceiverFrameDecoder.frame(video)
        try await Task.detached {
            try first.write(Data(stream.prefix(2)))
            try first.write(Data(stream.dropFirst(2)))
        }.value
        try await waitFor("real H264 parameter sets accepted") { receiver.videoSize == CGSize(width: 64, height: 64) }
        precondition(receiver.connected)
        if EncoderHardwareCapabilities.hevc, VTIsHardwareDecodeSupported(kCMVideoCodecType_HEVC) {
            let hevc = try await Task.detached { try receiverTestH264Frame(codec: kCMVideoCodecType_HEVC) }.value
            let hevcConfig = try JSONSerialization.data(withJSONObject: ["type":"streamConfig", "codec":"hevc", "width":64, "height":64])
            try first.write(ReceiverFrameDecoder.frame(hevcConfig) + ReceiverFrameDecoder.frame(hevc))
            try await waitFor("HEVC accepted") { receiver.status.contains("· HEVC") && receiver.videoSize.width == 64 }
            // Malformed HEVC asks once for H.264; queued HEVC video cannot contaminate the fallback parser.
            try first.write(ReceiverFrameDecoder.frame(Data([0,0,0,1,0x26,0])))
            try await waitFor("HEVC fallback requested") { receiver.status.contains("回退 H.264") }
            try first.write(ReceiverFrameDecoder.frame(hevc))
            try first.write(stream)
            try await waitFor("H264 after HEVC failure") { receiver.status.contains("· H.264") && receiver.videoSize.width == 64 }
        } else { print("SKIP HEVC network video: hardware codec unavailable") }
        try await Task.detached { try first.write(Data([255,255,255,255])); precondition(first.isClosed()) }.value
        try await waitFor("malformed peer disconnected") { !receiver.connected && receiver.videoSize == .zero }
        let next = try await Task.detached { () -> ReceiverTestPeer in
            let peer = try ReceiverTestPeer(port: port); _ = try peer.hello(); return peer
        }.value
        try await waitFor("reconnect") { receiver.connected }
        receiver.stop()
        receiver.start(port: 0, advertiseService: false)
        try await waitFor("fresh listener") { receiver.listeningPort != 0 && !receiver.connected }
        let freshPort = receiver.listeningPort
        let fresh = try await Task.detached { () -> ReceiverTestPeer in
            let peer = try ReceiverTestPeer(port: freshPort); _ = try peer.hello(); return peer
        }.value
        try await Task.sleep(for: .milliseconds(600))
        precondition(receiver.connected && receiver.listeningPort == freshPort, "old shutdown killed new session")
        receiver.disconnect()
        try await waitFor("disconnect retains listener") { !receiver.connected }
        precondition(receiver.listeningPort == freshPort)
        try await Task.detached {
            let invalid = try ReceiverTestPeer(port: freshPort)
            _ = try invalid.hello()
            let bad = try JSONSerialization.data(withJSONObject: ["type":"streamConfig", "codec":"h264", "width":64, "height":64, "fps":121])
            try invalid.write(ReceiverFrameDecoder.frame(bad))
            precondition(invalid.isClosed(), "out-of-envelope FPS accepted")
        }.value
        await withCheckedContinuation { continuation in receiver.stop { continuation.resume() } }
        try await waitFor("stopped") { receiver.listeningPort == 0 }
        withExtendedLifetime((first, next, fresh)) {}
        let legacy = StreamReceiver(hardwareHEVCDecode: false, securityProvider: { .legacy })
        legacy.start(port: 0, advertiseService: false)
        try await waitFor("legacy listen") { legacy.listeningPort != 0 }
        let legacyPort = legacy.listeningPort
        let unsupported = try await Task.detached { () -> ReceiverTestPeer in
            let peer = try ReceiverTestPeer(port: legacyPort)
            let hello = try peer.hello()
            precondition(hello["supportedCodecs"] as? [String] == ["h264"])
            let legacyCaps = Set(hello["capabilities"] as? [String] ?? [])
            precondition(legacyCaps.contains("udpMediaV1") && legacyCaps.contains("udpCursorV1")
                && legacyCaps.contains("udpAudioV1") && legacyCaps.contains("displayP3")
                && !legacyCaps.contains("hevc5kV1"))
            let cfg = try JSONSerialization.data(withJSONObject: ["type":"streamConfig", "codec":"hevc", "width":64, "height":64])
            try peer.write(ReceiverFrameDecoder.frame(cfg))
            let failure = try peer.hello()
            precondition(failure["type"] as? String == "codecFailure")
            return peer
        }.value
        try await waitFor("fallback timeout closes peer") { !legacy.connected && legacy.status.contains("回退超时") }
        await withCheckedContinuation { continuation in legacy.stop { continuation.resume() } }
        withExtendedLifetime(unsupported) {}

        // Verify C4 (orientation-independent 4K + live configure re-hello) + UDP cursor/audio/stale-config handling
        final class AudioSinkProbe: MacAudioPlaying, @unchecked Sendable {
            private let lock = NSLock()
            var isMuted = false
            private(set) var receivedBytes = 0
            private(set) var stops = 0
            func enqueueS16LE(_ pcmData: Data) { lock.withLock { receivedBytes += pcmData.count } }
            func stop() { lock.withLock { stops += 1 } }
        }
        let audioProbe = AudioSinkProbe()
        let upgraded = StreamReceiver(hardwareHEVCDecode: true, audioPlayer: audioProbe, securityProvider: { .legacy })
        upgraded.configure(panel: PanelAnnouncement(pixelsWide: 2560, pixelsHigh: 1440, scale: 2,
                           millimetersWide: 600, millimetersHigh: 340),
                           name: "UpgradedMac", maxFps: 60)
        upgraded.start(port: 0, advertiseService: false)
        try await waitFor("upgraded listen") { upgraded.listeningPort != 0 }
        let upgPort = upgraded.listeningPort
        var udpCursorPoint: (Double, Double, Bool)?
        upgraded.onCursor = { x, y, v in udpCursorPoint = (x, y, v) }
        let upgPeer = try await Task.detached { () -> ReceiverTestPeer in
            let peer = try ReceiverTestPeer(port: upgPort)
            let hello = try peer.hello()
            let caps = Set(hello["capabilities"] as? [String] ?? [])
            precondition(caps.contains("hevc5kV1") && caps.contains("displayP3")
                && caps.contains("udpCursorV1") && caps.contains("udpAudioV1"))
            return peer
        }.value
        // Portrait 2304x4096 H.264 streamConfig accepted on landscape 2560x1440 Mac panel
        let portraitCfg = try JSONSerialization.data(withJSONObject: [
            "type": "streamConfig", "codec": "h264", "width": 2304, "height": 4096, "fps": 60, "configVersion": 1
        ])
        try await Task.detached { try upgPeer.write(ReceiverFrameDecoder.frame(portraitCfg)) }.value
        // Switch to 64x64 configVersion=2 + live panel update without dropping stream
        let cfgV2 = try JSONSerialization.data(withJSONObject: [
            "type": "streamConfig", "codec": "h264", "width": 64, "height": 64, "fps": 60, "configVersion": 2
        ])
        try await Task.detached {
            try upgPeer.write(ReceiverFrameDecoder.frame(cfgV2) + ReceiverFrameDecoder.frame(video))
        }.value
        try await waitFor("upgraded video") { upgraded.videoSize == CGSize(width: 64, height: 64) }
        upgraded.configure(panel: PanelAnnouncement(pixelsWide: 1440, pixelsHigh: 2560, scale: 2,
                           millimetersWide: 340, millimetersHigh: 600),
                           name: "UpgradedMac", maxFps: 60)
        try await Task.detached {
            for _ in 0..<8 {
                let msg = try upgPeer.hello()
                if msg["type"] as? String == "hello",
                   msg["pixelsWide"] as? Int == 1440,
                   msg["pixelsHigh"] as? Int == 2560 {
                    return
                }
            }
            throw ReceiverTestFailure(message: "live configure did not emit updated hello")
        }.value
        precondition(upgraded.connected && upgraded.videoSize == CGSize(width: 64, height: 64),
                     "live panel configure must preserve active session and decoded video")

        if let udpSender = UDPMediaSenderSession(
            sessionEpoch: 1,
            wireGeneration: 1,
            initialBitrate: 30_000_000,
            bitrateBounds: 12_000_000...100_000_000,
            peerHost: "127.0.0.1",
            peerPort: nil
        ) {
            let udpCfgData = Data(udpSender.makeConfigMessage().jsonString.utf8)
            let readyPort = try await Task.detached { () -> UInt16 in
                try upgPeer.write(ReceiverFrameDecoder.frame(udpCfgData))
                for _ in 0..<8 {
                    let msg = try upgPeer.hello()
                    if msg["type"] as? String == "udpMediaReady", let p = msg["udpPort"] as? Int {
                        return UInt16(p)
                    }
                }
                throw ReceiverTestFailure(message: "missing udpMediaReady")
            }.value
            let stopsBeforeDuplicate = audioProbe.stops
            let duplicatePort = try await Task.detached { () -> UInt16 in
                let malformed = try JSONSerialization.data(withJSONObject: ["type": "udpMediaConfig", "sessionEpoch": 0])
                try upgPeer.write(ReceiverFrameDecoder.frame(malformed) + ReceiverFrameDecoder.frame(udpCfgData))
                for _ in 0..<8 {
                    let msg = try upgPeer.hello()
                    if msg["type"] as? String == "udpMediaReady", let p = msg["udpPort"] as? Int {
                        return UInt16(p)
                    }
                }
                throw ReceiverTestFailure(message: "missing duplicate udpMediaReady")
            }.value
            precondition(duplicatePort == readyPort && audioProbe.stops == stopsBeforeDuplicate,
                         "malformed or duplicate-epoch udpMediaConfig must preserve active UDP session and audio player")
            udpSender.configurePeer(host: "127.0.0.1", port: readyPort)
            try await waitFor("udp sender ready") { udpSender.isReady }
            // Stale configVersion=1 frame on UDP must be ignored without disconnecting
            _ = udpSender.sendFrame(annexB: Data([0, 0, 0, 1, 0x41, 0x9A]), isKeyframe: false, captureTimestampMs: 100, configVersion: 1)
            // Future configVersion=3 IDR arriving before TCP streamConfig(v3) must trigger immediate "kf" once streamConfig(v3) arrives
            _ = udpSender.sendFrame(annexB: video, isKeyframe: true, captureTimestampMs: 102, configVersion: 3)
            _ = udpSender.sendCursor(UDPMediaCursorPayload(sequence: 500, normalizedX: 0.75, normalizedY: 0.25, visible: true))
            _ = udpSender.sendAudio(UDPMediaAudioPayload(audioSeq: 10, captureTimestampMs: 101, pcmBytes: Data(repeating: 0x10, count: 960)))
            _ = udpSender.sendAudio(UDPMediaAudioPayload(audioSeq: 10, captureTimestampMs: 101, pcmBytes: Data(repeating: 0x11, count: 960)))
            _ = udpSender.sendAudio(UDPMediaAudioPayload(audioSeq: 9, captureTimestampMs: 100, pcmBytes: Data(repeating: 0x12, count: 960)))
            _ = udpSender.sendAudio(UDPMediaAudioPayload(audioSeq: 11, captureTimestampMs: 106, pcmBytes: Data(repeating: 0x13, count: 960)))
            try await waitFor("udp cursor + monotonic audio") {
                udpCursorPoint != nil && audioProbe.receivedBytes >= 1920
            }
            precondition(audioProbe.receivedBytes == 1920,
                         "duplicate or out-of-order audioSeq packets must be dropped before enqueueing PCM")
            let cfgV3 = try JSONSerialization.data(withJSONObject: [
                "type": "streamConfig", "codec": "h264", "width": 64, "height": 64, "fps": 60, "configVersion": 3
            ])
            try await Task.detached {
                try upgPeer.write(ReceiverFrameDecoder.frame(cfgV3))
                for _ in 0..<8 {
                    let msg = try upgPeer.hello()
                    if msg["type"] as? String == "kf" { return }
                }
                throw ReceiverTestFailure(message: "streamConfig after ahead-of-order UDP frame did not request kf")
            }.value
            precondition(upgraded.connected, "stale or ahead-of-order UDP configVersion must not disconnect receiver")
            udpSender.stop()
        }
        await withCheckedContinuation { continuation in upgraded.stop { continuation.resume() } }
        precondition(audioProbe.stops >= 1, "stopping receiver must stop audio player")
        withExtendedLifetime(upgPeer) {}

        // Verify portrait Mac monitor capability clamping + odd inset clamping + live Annex-B swapped (w,h)==(cfgH,cfgW) rotation
        let oddPanel = StreamReceiver.resolvedPanel(
            PanelAnnouncement(pixelsWide: 2235, pixelsHigh: 3457, scale: 2, millimetersWide: 210, millimetersHigh: 325)
        )
        precondition(oddPanel.pixelsWide == 2234 && oddPanel.pixelsHigh == 3456,
                     "resolvedPanel must clamp odd panel dimensions to even pixels")
        let portraitMac = StreamReceiver(hardwareHEVCDecode: true, securityProvider: { .legacy })
        portraitMac.configure(
            panel: PanelAnnouncement(pixelsWide: 2234, pixelsHigh: 3456, scale: 2, millimetersWide: 210, millimetersHigh: 325),
            name: "PortraitMac",
            maxFps: 120
        )
        portraitMac.start(port: 0, advertiseService: false)
        try await waitFor("portrait mac listen") { portraitMac.listeningPort != 0 }
        let portraitPort = portraitMac.listeningPort
        let portraitPeer = try await Task.detached { () -> ReceiverTestPeer in
            let peer = try ReceiverTestPeer(port: portraitPort)
            let hello = try peer.hello()
            let videoCaps = hello["videoCaps"] as? [[String: Any]] ?? []
            precondition(!videoCaps.isEmpty && videoCaps.count <= 16,
                         "advertised videoCaps must remain within protocol 16-entry cap")
            let firstCap = videoCaps[0]
            precondition(firstCap["maxWidth"] as? Int == 2304 && firstCap["maxHeight"] as? Int == 4096,
                         "portrait Mac panel must advertise portrait 4K envelope first")
            precondition(videoCaps.contains { ($0["maxWidth"] as? Int) == 2234 && ($0["maxHeight"] as? Int) == 3456 && ($0["maxFrameRate"] as? Int) == 120 },
                         "portrait ProMotion Mac panel must advertise native 120Hz portrait envelope")
            return peer
        }.value
        precondition(portraitMac.acceptsStreamConfiguration(["codec": "hevc", "width": 3000, "height": 3000, "fps": 60]) == nil,
                     "out-of-envelope 3000x3000 short edge > 2880 must be rejected at streamConfig time")
        precondition(portraitMac.acceptsStreamConfiguration(["codec": "hevc", "width": 2234, "height": 3456, "fps": 120]) != nil,
                     "portrait native 2234x3456 @ 120Hz must be accepted")
        precondition(portraitMac.acceptsStreamConfiguration(["codec": "hevc", "width": 3456, "height": 2234, "fps": 120]) != nil,
                     "rotated landscape native 3456x2234 @ 120Hz must be accepted")

        let portraitFrame = try await Task.detached { try receiverTestH264Frame(width: 64, height: 96) }.value
        let landscapeFrame = try await Task.detached { try receiverTestH264Frame(width: 96, height: 64) }.value
        let initialPortraitCfg = try JSONSerialization.data(withJSONObject: [
            "type": "streamConfig", "codec": "h264", "width": 64, "height": 96, "fps": 60, "configVersion": 1
        ])
        try await Task.detached {
            try portraitPeer.write(ReceiverFrameDecoder.frame(initialPortraitCfg) + ReceiverFrameDecoder.frame(portraitFrame))
        }.value
        try await waitFor("portrait 64x96 video") { portraitMac.videoSize == CGSize(width: 64, height: 96) }
        // Live orientation switch: send swapped 96x64 keyframe BEFORE new streamConfig — must NOT disconnect with "视频尺寸与配置不符"!
        try await Task.detached {
            try portraitPeer.write(ReceiverFrameDecoder.frame(landscapeFrame))
        }.value
        try await waitFor("swapped 96x64 live rotation") { portraitMac.videoSize == CGSize(width: 96, height: 64) }
        precondition(portraitMac.connected && !portraitMac.status.contains("视频尺寸与配置不符"),
                     "swapped (w, h) == (cfgH, cfgW) across live orientation switch must never disconnect")
        await withCheckedContinuation { continuation in portraitMac.stop { continuation.resume() } }
        withExtendedLifetime(portraitPeer) {}

        print("Mac receiver loopback: hello, cursor coalescing, diagnostics, busy rejection, H264, invalid framing, reconnect, stop/restart PASS")
    }
}

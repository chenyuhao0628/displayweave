import Foundation
import Darwin
import AVFoundation
import VideoToolbox

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
        let receiver = StreamReceiver(securityProvider: { .legacy })
        receiver.configure(panel: PanelAnnouncement(pixelsWide: 1920, pixelsHigh: 1080, scale: 1),
                           name: "Test", maxFps: 120)
        receiver.start(port: 0, advertiseService: false)
        try await waitFor("listen") { receiver.listeningPort != 0 }
        let port = receiver.listeningPort
        let first = try await Task.detached { () -> ReceiverTestPeer in
            let peer = try ReceiverTestPeer(port: port)
            let hello = try peer.hello()
            precondition(hello["device"] as? String == "Mac")
            precondition(hello["maxFps"] as? Int == 120)
            precondition((hello["supportedCodecs"] as? [String])?.contains("h264") == true)
            precondition(hello["protocolVersion"] == nil && hello["power"] == nil && hello["cursorPort"] == nil)
            return peer
        }.value
        try await waitFor("connected") { receiver.connected }
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
            let cfg = try JSONSerialization.data(withJSONObject: ["type":"streamConfig", "codec":"hevc", "width":64, "height":64])
            try peer.write(ReceiverFrameDecoder.frame(cfg))
            let failure = try peer.hello()
            precondition(failure["type"] as? String == "codecFailure")
            return peer
        }.value
        try await waitFor("fallback timeout closes peer") { !legacy.connected && legacy.status.contains("回退超时") }
        await withCheckedContinuation { continuation in legacy.stop { continuation.resume() } }
        withExtendedLifetime(unsupported) {}
        print("Mac receiver loopback: hello, busy rejection, H264, invalid framing, reconnect, stop/restart PASS")
    }
}

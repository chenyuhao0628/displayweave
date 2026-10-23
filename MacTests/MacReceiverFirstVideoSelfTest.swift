import Foundation
import AVFoundation

private final class FirstVideoProbe: MacVideoRendering, @unchecked Sendable {
    private let lock = NSLock()
    private var time: TimeInterval = 0
    private var samples = 0
    private var failed = false
    var now: TimeInterval { lock.withLock { time } }
    var count: Int { lock.withLock { samples } }
    var status: AVQueuedSampleBufferRenderingStatus { lock.withLock { failed ? .failed : .rendering } }
    var isReadyForMoreMediaData: Bool { true }
    func advance(to time: TimeInterval) { lock.withLock { self.time = time } }
    func fail() { lock.withLock { failed = true } }
    func enqueue(_ sample: CMSampleBuffer) { lock.withLock { samples += 1 } }
    func flush(removingDisplayedImage: Bool) { lock.withLock { failed = false } }
}

@main struct MacReceiverFirstVideoSelfTest {
    @MainActor static func waitFor(_ description: String, _ condition: () -> Bool) async throws {
        for _ in 0..<100 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(20))
        }
        throw ReceiverTestFailure(message: "timeout: \(description)")
    }

    static func connect(_ port: UInt16) async throws -> ReceiverTestPeer {
        try await Task.detached {
            let peer = try ReceiverTestPeer(port: port); _ = try peer.hello(); return peer
        }.value
    }

    static func send(_ frames: [Data], to peer: ReceiverTestPeer) async throws {
        try await Task.detached {
            var batch = Data()
            for frame in frames { batch.append(ReceiverFrameDecoder.frame(frame)) }
            batch.append(ReceiverFrameDecoder.frame(Data(#"{"type":"ping","t":9182}"#.utf8)))
            try peer.write(batch)
            for _ in 0..<32 {
                let message = try peer.hello()
                if message["type"] as? String == "pong", message["t"] as? Int == 9182 { return }
            }
            throw ReceiverTestFailure(message: "parse fence timeout")
        }.value
    }

    @MainActor static func main() async throws {
        let probe = FirstVideoProbe()
        let receiver = StreamReceiver(hardwareHEVCDecode: false, videoRenderer: probe,
            monotonicTime: { probe.now }, securityProvider: { .legacy })
        receiver.start(port: 0, advertiseService: false)
        try await waitFor("listen") { receiver.listeningPort != 0 }
        let port = receiver.listeningPort
        let first = try await connect(port)
        try await waitFor("connected") { receiver.connected }
        try await send([], to: first) // a real heartbeat must not mask missing video
        probe.advance(to: 16)
        try await waitFor("heartbeat-only connection must fail its first-video deadline") { !receiver.connected }
        precondition(receiver.status.contains("首帧") && receiver.status.contains("屏幕录制"))
        try await Task.detached {
            for _ in 0..<32 {
                if try first.hello()["type"] as? String == "closing" { return }
            }
            throw ReceiverTestFailure(message: "first-video failure must ask the sender to end this session")
        }.value

        let config = Data(#"{"type":"streamConfig","codec":"h264","width":64,"height":64,"fps":60}"#.utf8)
        let video = try await Task.detached { try receiverTestH264Frame() }.value
        // Valid parameter sets and repeated configuration are not a video frame.
        var parser = ReceiverVideoBitstream(codec: .h264)
        let parsed = try parser.parse(video)
        precondition(parsed.keyframe && !parsed.slices.isEmpty)
        var parameterSets = Data()
        let nalus = video.splitAnnexBForFirstVideoTest()
        for nalu in nalus where [7, 8].contains(Int(nalu.first! & 0x1f)) {
            parameterSets.append(contentsOf: [0, 0, 0, 1]); parameterSets.append(nalu)
        }
        precondition(!parameterSets.isEmpty)
        probe.advance(to: 100)
        let second = try await connect(port)
        try await waitFor("replacement connected") { receiver.connected }
        try await send([config, parameterSets], to: second)
        probe.advance(to: 114)
        try await send([config], to: second)
        try await Task.sleep(for: .milliseconds(1100))
        precondition(receiver.connected && receiver.status.contains("等待画面") && probe.count == 0)
        probe.advance(to: 116)
        try await waitFor("configuration cannot extend an unfulfilled first-video deadline") { !receiver.connected }

        // A new connection gets its own budget; one valid frame satisfies it.
        probe.advance(to: 200)
        let third = try await connect(port)
        try await waitFor("third connected") { receiver.connected }
        try await send([config, video], to: third)
        try await waitFor("valid frame submitted") { receiver.videoSize.width == 64 }
        let submitted = probe.count
        precondition(submitted == 1)
        probe.advance(to: 500)
        try await send([config], to: third) // identical bitrate/config updates do not erase a static picture
        try await Task.sleep(for: .milliseconds(1100))
        precondition(receiver.connected && probe.count == submitted,
            "a static desktop after its first frame must not need periodic new frames")

        // A changed configuration expects fresh video, but repeating it cannot restart that wait.
        let resized = Data(#"{"type":"streamConfig","codec":"h264","width":128,"height":64,"fps":60}"#.utf8)
        try await send([resized], to: third)
        probe.advance(to: 514)
        try await send([resized], to: third)
        probe.advance(to: 516)
        try await waitFor("new configuration needs a new first frame") { !receiver.connected }

        // Preserve the timed HEVC -> H.264 fallback and accept its first frame.
        probe.advance(to: 600)
        let fourth = try await connect(port)
        let hevc = Data(#"{"type":"streamConfig","codec":"hevc","width":64,"height":64,"fps":60}"#.utf8)
        try await send([hevc], to: fourth)
        try await waitFor("fallback") { receiver.status.contains("回退 H.264") }
        try await send([config, video], to: fourth)
        try await waitFor("fallback video") { receiver.videoSize.width == 64 }
        probe.advance(to: 700)
        try await Task.sleep(for: .milliseconds(1100))
        precondition(receiver.connected)
        probe.fail()
        try await waitFor("asynchronous H264 renderer failure must surface without another frame") { !receiver.connected }
        precondition(receiver.status.contains("解码失败"))
        await withCheckedContinuation { continuation in receiver.stop { continuation.resume() } }
        withExtendedLifetime((first, second, third, fourth)) {}
        print("Mac first video: heartbeat-only deadline, parameter sets, repeated config, static desktop, replacement and fallback PASS")
    }
}

private extension Data {
    /// Synthetic VideoToolbox fixture uses four-byte Annex B start codes.
    func splitAnnexBForFirstVideoTest() -> [Data] {
        var starts: [Int] = []
        guard count >= 4 else { return [] }
        for i in 0...(count - 4) where self[i..<(i + 4)] == Data([0, 0, 0, 1]) { starts.append(i) }
        return starts.enumerated().map { index, start in
            Data(self[(start + 4)..<(index + 1 < starts.count ? starts[index + 1] : count)])
        }
    }
}

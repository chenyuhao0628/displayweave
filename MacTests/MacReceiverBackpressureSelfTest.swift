import Foundation
import AVFoundation

private final class RendererProbe: MacVideoRendering, @unchecked Sendable {
    private let lock = NSLock()
    private var ready = true
    private var failed = false
    private var time: TimeInterval = 0
    private var samples = 0
    private var flushes = 0
    var status: AVQueuedSampleBufferRenderingStatus { lock.withLock { failed ? .failed : .rendering } }
    var isReadyForMoreMediaData: Bool { lock.withLock { ready } }
    var now: TimeInterval { lock.withLock { time } }
    var counts: (samples: Int, flushes: Int) { lock.withLock { (samples, flushes) } }
    func set(ready: Bool, time: TimeInterval, failed: Bool = false) {
        lock.withLock { self.ready = ready; self.time = time; self.failed = failed }
    }
    func enqueue(_ sample: CMSampleBuffer) { lock.withLock { samples += 1 } }
    func flush(removingDisplayedImage: Bool) { lock.withLock { flushes += 1 } }
}

@main struct MacReceiverBackpressureSelfTest {
    @MainActor static func waitFor(_ condition: () -> Bool) async throws {
        for _ in 0..<100 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(20))
        }
        throw ReceiverTestFailure(message: "receiver state timeout")
    }

    /// A pong fences parsing and renderer submission on the production receive queue.
    static func send(_ frames: [Data], to peer: ReceiverTestPeer) async throws {
        try await Task.detached {
            var batch = Data()
            for frame in frames { batch.append(ReceiverFrameDecoder.frame(frame)) }
            batch.append(ReceiverFrameDecoder.frame(Data(#"{"type":"ping","t":7319}"#.utf8)))
            try peer.write(batch)
            for _ in 0..<32 {
                let message = try peer.hello()
                if message["type"] as? String == "pong", message["t"] as? Int == 7319 { return }
            }
            throw ReceiverTestFailure(message: "renderer fence timeout")
        }.value
    }

    @MainActor static func main() async throws {
        let probe = RendererProbe()
        let receiver = StreamReceiver(hardwareHEVCDecode: false, videoRenderer: probe,
            monotonicTime: { probe.now }, securityProvider: { .legacy })
        receiver.start(port: 0, advertiseService: false)
        try await waitFor { receiver.listeningPort != 0 }
        let port = receiver.listeningPort
        let peer = try await Task.detached { () -> ReceiverTestPeer in
            let peer = try ReceiverTestPeer(port: port); _ = try peer.hello(); return peer
        }.value
        let frames = try await Task.detached { try receiverTestVideoFrames(count: 2) }.value
        var parser = ReceiverVideoBitstream(codec: .h264)
        let keyframe = try parser.parse(frames[0])
        let dependent = try parser.parse(frames[1])
        precondition(keyframe.keyframe)
        precondition(!dependent.keyframe, "test requires an encoded dependent frame")
        let config = Data(#"{"type":"streamConfig","codec":"h264","width":64,"height":64,"fps":60}"#.utf8)
        try await send([config, frames[0]], to: peer)
        let start = probe.counts

        probe.set(ready: false, time: 1)
        try await send([frames[1]], to: peer)
        precondition(probe.counts.samples == start.samples + 1 && probe.counts.flushes == start.flushes,
            "one transient not-ready frame must preserve the decoder reference chain")
        probe.set(ready: false, time: 1.016)
        try await send([frames[1]], to: peer)
        probe.set(ready: true, time: 1.032)
        try await send([frames[1]], to: peer)
        precondition(probe.counts.samples == start.samples + 3 && probe.counts.flushes == start.flushes,
            "short backpressure must recover without requesting a replacement keyframe")

        let beforeOverflow = probe.counts
        probe.set(ready: false, time: 2)
        try await send(Array(repeating: frames[1], count: 200), to: peer)
        precondition(probe.counts.samples == beforeOverflow.samples + 2,
            "sustained backpressure must admit at most two additional frames")
        precondition(probe.counts.flushes == beforeOverflow.flushes + 1,
            "sustained backpressure flushes once, not once per discarded frame")
        try await send([frames[0]], to: peer)
        precondition(probe.counts.samples == beforeOverflow.samples + 2,
            "keyframes cannot bypass an exhausted renderer budget")
        probe.set(ready: true, time: 2.020)
        try await send([frames[1]], to: peer)
        precondition(probe.counts.samples == beforeOverflow.samples + 2,
            "after flush, dependent frames must wait for a keyframe")
        try await send([frames[0], frames[1]], to: peer)
        precondition(probe.counts.samples == beforeOverflow.samples + 4,
            "ready renderer resumes at a keyframe")

        let beforeTimeout = probe.counts
        probe.set(ready: false, time: 3)
        try await send([frames[1]], to: peer)
        probe.set(ready: false, time: 3.051)
        try await send([frames[1]], to: peer)
        precondition(probe.counts.samples == beforeTimeout.samples + 1
            && probe.counts.flushes == beforeTimeout.flushes + 1,
            "50 ms time bound applies even before the two-frame allowance is used")

        receiver.disconnect()
        try await waitFor { !receiver.connected }
        let fresh = try await Task.detached { () -> ReceiverTestPeer in
            let peer = try ReceiverTestPeer(port: port); _ = try peer.hello(); return peer
        }.value
        let beforeReplacement = probe.counts.samples
        probe.set(ready: false, time: 4)
        try await send([config, frames[0]], to: fresh)
        precondition(probe.counts.samples == beforeReplacement + 1,
            "retired backpressure must not block the replacement session")
        probe.set(ready: true, time: 4.016, failed: true)
        try await Task.detached { try fresh.write(ReceiverFrameDecoder.frame(frames[1])); precondition(fresh.isClosed()) }.value
        try await waitFor { !receiver.connected }
        await withCheckedContinuation { continuation in receiver.stop { continuation.resume() } }
        print("MacReceiverBackpressureSelfTest PASS: transient pressure, bounded overload, keyframe recovery, timeout, replacement, decoder failure")
    }
}

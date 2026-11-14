import Foundation

private func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() { fatalError(message) }
}

@main
struct UDPMediaTransportSelfTest {
    static func main() {
        let readySem = DispatchSemaphore(value: 0)
        let framesSem = DispatchSemaphore(value: 0)
        let lock = NSLock()
        var receivedFrames: [UDPMediaFrameEnvelope] = []

        guard let sender = UDPMediaSenderSession(
            sessionEpoch: 99,
            wireGeneration: 1,
            initialBitrate: 50_000_000,
            bitrateBounds: 10_000_000...100_000_000,
            peerHost: nil,
            peerPort: nil
        ) else {
            fatalError("Failed to initialize UDPMediaSenderSession")
        }
        defer { sender.stop() }

        sender.onReady = { gen, epoch in
            if gen == 1 && epoch == 99 {
                readySem.signal()
            }
        }

        let configMsg = sender.makeConfigMessage()
        guard let receiver = UDPMediaReceiverSession(
            config: configMsg,
            generation: 1,
            senderHost: "127.0.0.1"
        ) else {
            fatalError("Failed to initialize UDPMediaReceiverSession")
        }
        defer { receiver.stop() }

        receiver.onFrameReady = { gen, frame in
            guard gen == 1 else { return }
            lock.lock()
            receivedFrames.append(frame)
            let count = receivedFrames.count
            lock.unlock()
            if count >= 5 {
                framesSem.signal()
            }
        }

        // Wait for UDP probe handshake over 127.0.0.1
        expect(readySem.wait(timeout: .now() + 2.0) == .success && sender.isReady,
               "UDP probe handshake must make sender session ready on loopback")

        // Send 5 multi-fragment video frames (1 keyframe + 4 P-frames)
        var samplePayloads: [Data] = []
        for idx in 0..<5 {
            let length = 4000 + idx * 500
            var bytes = [UInt8](repeating: 0, count: length)
            for b in 0..<length {
                bytes[b] = UInt8((b + idx) & 0xFF)
            }
            samplePayloads.append(Data(bytes))
        }
        for (idx, payload) in samplePayloads.enumerated() {
            let sent = sender.sendFrame(
                annexB: payload,
                isKeyframe: idx == 0,
                captureTimestampMs: 1_700_000_001_000 + Int64(idx * 16),
                configVersion: 3
            )
            expect(sent, "sendFrame must succeed while UDP session is ready")
            Thread.sleep(forTimeInterval: 0.008)
        }

        expect(framesSem.wait(timeout: .now() + 2.0) == .success,
               "all 5 multi-fragment frames must be reassembled and delivered over UDP loopback")

        lock.lock()
        let delivered = receivedFrames
        lock.unlock()
        expect(delivered.count == 5, "exactly 5 frames delivered")
        for i in 0..<5 {
            expect(delivered[i].annexB == samplePayloads[i],
                   "frame \(i) Annex-B payload matches over UDP loopback")
            expect(delivered[i].configVersion == 3, "frame \(i) configVersion preserved")
        }

        // Stop must immediately deactivate session
        sender.stop()
        expect(!sender.isReady, "stopped UDPMediaSenderSession is no longer ready")
        expect(!sender.sendFrame(annexB: samplePayloads[0], isKeyframe: true, captureTimestampMs: 1, configVersion: 3),
               "stopped UDPMediaSenderSession rejects new frames so caller falls back to TCP")

        print("UDPMediaTransportSelfTest PASS")
    }
}

import Darwin
import Foundation

private func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() { fatalError(message) }
}

private func runLoopbackTransportCheck(
    host: String,
    boundInterfaceName: String?,
    sessionEpoch: Int64
) {
    let readySem = DispatchSemaphore(value: 0)
    let framesSem = DispatchSemaphore(value: 0)
    let lock = NSLock()
    var receivedFrames: [UDPMediaFrameEnvelope] = []
    var completedFrameSignals = 0
    var totalSentBytesReported = 0

    guard let sender = UDPMediaSenderSession(
        sessionEpoch: sessionEpoch,
        wireGeneration: 1,
        initialBitrate: 50_000_000,
        bitrateBounds: 10_000_000...100_000_000,
        peerHost: nil,
        peerPort: nil,
        boundInterfaceName: boundInterfaceName
    ) else {
        fatalError("Failed to initialize UDPMediaSenderSession (\(host), if=\(boundInterfaceName ?? "nil"))")
    }
    defer { sender.stop() }

    sender.onReady = { gen, epoch in
        if gen == 1 && epoch == sessionEpoch {
            readySem.signal()
        }
    }
    sender.onBytesSent = { bytes, completedFrame in
        lock.lock()
        totalSentBytesReported += bytes
        if completedFrame {
            completedFrameSignals += 1
        }
        lock.unlock()
    }

    let configMsg = sender.makeConfigMessage()
    guard let receiver = UDPMediaReceiverSession(
        config: configMsg,
        generation: 1,
        senderHost: host,
        boundInterfaceName: boundInterfaceName
    ) else {
        fatalError("Failed to initialize UDPMediaReceiverSession (\(host), if=\(boundInterfaceName ?? "nil"))")
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

    expect(readySem.wait(timeout: .now() + 2.0) == .success && sender.isReady,
           "UDP probe handshake must make sender session ready on \(host) (if=\(boundInterfaceName ?? "any"))")

    // Verify pre-FEC wire budget vs post-FEC encoder bitrate separation
    sender.updateEncoderLoadCeiling(35_000_000)
    let cappedSnap = sender.snapshotBitrateBudgets()
    expect(cappedSnap.bweBitrateBps == 50_000_000
            && cappedSnap.wireBudgetBps == 35_000_000
            && cappedSnap.pacerRateBps == UDPDebtPacer.pacingRate(forTargetBitrateBps: 35_000_000)
            && cappedSnap.effectiveEncoderBps < 35_000_000,
           "updateEncoderLoadCeiling caps wire budget without overwriting bwe.currentBitrate with post-FEC bitrate")

    sender.updateEncoderLoadCeiling(nil)
    sender.syncManualTargetBitrate(60_000_000)
    let manualSnap = sender.snapshotBitrateBudgets()
    expect(manualSnap.bweBitrateBps == 60_000_000
            && manualSnap.wireBudgetBps == 60_000_000
            && manualSnap.pacerRateBps == UDPDebtPacer.pacingRate(forTargetBitrateBps: 60_000_000)
            && manualSnap.effectiveEncoderBps < 60_000_000,
           "syncManualTargetBitrate keeps pacer on pre-FEC wire budget while effectiveEncoderBps deducts FEC")

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
        expect(sent, "sendFrame must succeed while UDP session is ready on \(host)")
        Thread.sleep(forTimeInterval: 0.008)
    }

    expect(framesSem.wait(timeout: .now() + 2.0) == .success,
           "all 5 multi-fragment frames must be reassembled and delivered over \(host)")

    // Wait briefly across idle 1ms pacer ticks to verify completedFrame never increments on idle ticks
    Thread.sleep(forTimeInterval: 0.025)

    lock.lock()
    let delivered = receivedFrames
    let frameSignals = completedFrameSignals
    let sentBytes = totalSentBytesReported
    lock.unlock()

    expect(delivered.count == 5, "exactly 5 frames delivered on \(host)")
    for i in 0..<5 {
        expect(delivered[i].annexB == samplePayloads[i],
               "frame \(i) Annex-B payload matches over \(host)")
        expect(delivered[i].configVersion == 3, "frame \(i) configVersion preserved")
    }
    expect(frameSignals == 5 && sentBytes > 20_000,
           "onBytesSent marks completedFrame == true exactly once per .endOfFrame video frame (got \(frameSignals))")

    // Stop must immediately deactivate session
    sender.stop()
    expect(!sender.isReady, "stopped UDPMediaSenderSession is no longer ready")
    expect(!sender.sendFrame(annexB: samplePayloads[0], isKeyframe: true, captureTimestampMs: 1, configVersion: 3),
           "stopped UDPMediaSenderSession rejects new frames so caller falls back to TCP")
}

private func runReceiverProbeRetryCheck() throws {
    let secret = UDPMediaKeyMaterial.generateRootSecret()
    let sessionEpoch: Int64 = 303
    let keys = try UDPMediaKeyMaterial.derive(rootSecret: secret, sessionEpoch: sessionEpoch)
    let probeQueue = DispatchQueue(label: "app.displayweave.udp.test.probe")
    let secondProbeSem = DispatchSemaphore(value: 0)
    let lock = NSLock()
    var probeSeqs: [UInt64] = []
    var serverCrypto = UDPMediaCryptoSession(keyMaterial: keys)
    var probeSocketRef: NonBlockingUDPSocket?

    guard let mockServerSocket = NonBlockingUDPSocket(
        preferIPv6: false,
        boundInterfaceName: "lo0",
        queue: probeQueue,
        onReceive: { data, peer in
            guard let pkt = try? serverCrypto.open(datagram: data, expectedDirection: .receiverToSender),
                  pkt.header.packetType == .probe else {
                return
            }
            lock.lock()
            probeSeqs.append(pkt.extendedSequence)
            let count = probeSeqs.count
            lock.unlock()
            // Intentionally drop Probe #1 to simulate Wi-Fi loss; acknowledge Probe #2 (~150ms later)!
            if count == 2 {
                if let (ackDg, _, _) = try? serverCrypto.seal(
                    direction: .senderToReceiver,
                    packetType: .probe,
                    flags: [.probeAck],
                    sendTimeUs: 1000,
                    frameId: 0,
                    fragIndex: 0,
                    fragCount: 1,
                    payload: Data("DWV1-PROBE".utf8)
                ) {
                    _ = probeSocketRef?.send(ackDg, to: peer)
                }
                secondProbeSem.signal()
            }
        }
    ) else {
        fatalError("Failed to open mock server socket on lo0")
    }
    probeSocketRef = mockServerSocket
    defer { mockServerSocket.close() }

    let config = UDPMediaConfigMessage(
        sessionEpoch: sessionEpoch,
        udpPort: mockServerSocket.localPort,
        rootSecret: secret
    )
    guard let receiver = UDPMediaReceiverSession(
        config: config,
        generation: 7,
        senderHost: "127.0.0.1",
        boundInterfaceName: "lo0"
    ) else {
        fatalError("Failed to create receiver for probe retry check")
    }
    defer { receiver.stop() }

    expect(secondProbeSem.wait(timeout: .now() + 1.0) == .success,
           "UDPMediaReceiverSession must retry initial UDP probe (~150ms) when first probe goes unanswered")
    // After receiving probeAck, receiver must stop sending initial probes
    Thread.sleep(forTimeInterval: 0.22)
    lock.lock()
    let finalCount = probeSeqs.count
    lock.unlock()
    expect(finalCount == 2, "UDPMediaReceiverSession stops retrying initial probes once sender responds (got \(finalCount))")
}

@main
struct UDPMediaTransportSelfTest {
    static func main() throws {
        // 1. Socket interface binding validation & closed/failed send return value
        let testQueue = DispatchQueue(label: "app.displayweave.udp.test.sock")
        let invalidIfSock = NonBlockingUDPSocket(
            preferIPv6: true,
            boundInterfaceName: "nonexistent_if99",
            queue: testQueue,
            onReceive: { _, _ in }
        )
        expect(invalidIfSock == nil, "NonBlockingUDPSocket must fail cleanly for unknown boundInterfaceName")

        guard let v4OnlySock = NonBlockingUDPSocket(
            preferIPv6: false,
            boundInterfaceName: "lo0",
            queue: testQueue,
            onReceive: { _, _ in }
        ) else {
            fatalError("Failed to open AF_INET socket bound to lo0")
        }
        expect(v4OnlySock.boundInterfaceIndex > 0, "lo0 resolves to non-zero interface index")
        if let pureV6Dest = UDPEndpointResolver.resolveSockAddr(host: "::1", port: 9999) {
            expect(!v4OnlySock.send(Data([0x01, 0x02]), to: pureV6Dest),
                   "AF_INET socket rejects pure IPv6 destination cleanly with false")
        }
        let v4Dest = UDPEndpointResolver.resolveSockAddr(host: "127.0.0.1", port: v4OnlySock.localPort)!
        v4OnlySock.close()
        expect(!v4OnlySock.send(Data([0x01]), to: v4Dest),
               "closed NonBlockingUDPSocket.send must return false")

        // Verify UDPEndpointResolver IPv6 preference even before peerPort is known
        expect(UDPEndpointResolver.prefersIPv6(host: nil), "unbound socket defaults to dual-stack IPv6")
        expect(UDPEndpointResolver.prefersIPv6(host: "::1"), "::1 prefers IPv6")
        expect(UDPEndpointResolver.prefersIPv6(host: "fe80::1%lo0"), "link-local IPv6 prefers IPv6")
        expect(!UDPEndpointResolver.prefersIPv6(host: "127.0.0.1"), "explicit IPv4 literal prefers AF_INET")

        // 2. End-to-end loopback over IPv4 (127.0.0.1) against dual-stack unbound sender + lo0 binding
        runLoopbackTransportCheck(host: "127.0.0.1", boundInterfaceName: nil, sessionEpoch: 99)
        runLoopbackTransportCheck(host: "127.0.0.1", boundInterfaceName: "lo0", sessionEpoch: 100)

        // 3. End-to-end loopback over IPv6 (::1) + IPV6_BOUND_IF on lo0
        runLoopbackTransportCheck(host: "::1", boundInterfaceName: nil, sessionEpoch: 101)
        runLoopbackTransportCheck(host: "::1", boundInterfaceName: "lo0", sessionEpoch: 102)

        // 4. Receiver multi-probe retry (~150ms spacing) on dropped initial probe
        try runReceiverProbeRetryCheck()

        print("UDPMediaTransportSelfTest PASS")
    }
}

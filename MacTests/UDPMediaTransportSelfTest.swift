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
    let cursorSem = DispatchSemaphore(value: 0)
    let audioSem = DispatchSemaphore(value: 0)
    let lock = NSLock()
    var receivedFrames: [UDPMediaFrameEnvelope] = []
    var receivedCursors: [UDPMediaCursorPayload] = []
    var receivedAudios: [UDPMediaAudioPayload] = []
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
    receiver.onCursor = { gen, cursor in
        guard gen == 1 else { return }
        lock.lock()
        receivedCursors.append(cursor)
        if cursor.sequence == 12 {
            cursorSem.signal()
        }
        lock.unlock()
    }
    receiver.onAudio = { gen, audio in
        guard gen == 1 else { return }
        lock.lock()
        receivedAudios.append(audio)
        if receivedAudios.count >= 2 {
            audioSem.signal()
        }
        lock.unlock()
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

    // Send cursor updates (including stale sequence 11 after sequence 12 to verify monotonic filter)
    expect(sender.sendCursor(UDPMediaCursorPayload(sequence: 10, normalizedX: Float32(0.25), normalizedY: Float32(0.5), visible: true)),
           "sendCursor(10) succeeds")
    Thread.sleep(forTimeInterval: 0.004)
    expect(sender.sendCursor(UDPMediaCursorPayload(sequence: 12, normalizedX: Float32(0.75), normalizedY: Float32(0.125), visible: true)),
           "sendCursor(12) succeeds")
    Thread.sleep(forTimeInterval: 0.004)
    expect(sender.sendCursor(UDPMediaCursorPayload(sequence: 11, normalizedX: Float32(0.1), normalizedY: Float32(0.1), visible: false)),
           "sendCursor(11) transmits")

    // Send 2 S16LE stereo audio packets
    let pcm1 = Data((0..<960).map { UInt8($0 & 0xFF) })
    let pcm2 = Data((0..<960).map { UInt8(($0 + 7) & 0xFF) })
    expect(sender.sendAudio(UDPMediaAudioPayload(audioSeq: 1, captureTimestampMs: 1_700_000_002_000, sampleRate: 48_000, channels: 2, pcmBytes: pcm1)),
           "sendAudio(1) succeeds")
    expect(sender.sendAudio(UDPMediaAudioPayload(audioSeq: 2, captureTimestampMs: 1_700_000_002_005, sampleRate: 48_000, channels: 2, pcmBytes: pcm2)),
           "sendAudio(2) succeeds")

    expect(framesSem.wait(timeout: .now() + 2.0) == .success,
           "all 5 multi-fragment frames must be reassembled and delivered over \(host)")
    expect(cursorSem.wait(timeout: .now() + 2.0) == .success,
           "cursor updates must be delivered over \(host)")
    expect(audioSem.wait(timeout: .now() + 2.0) == .success,
           "audio packets must be delivered over \(host)")

    // Wait briefly across idle 1ms pacer ticks to verify completedFrame never increments on idle ticks or cursor/audio
    Thread.sleep(forTimeInterval: 0.025)

    lock.lock()
    let delivered = receivedFrames
    let cursors = receivedCursors
    let audios = receivedAudios
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
    expect(cursors.last?.sequence == 12 && !cursors.contains(where: { $0.sequence == 11 }),
           "receiver drops out-of-order older cursor sequence 11 after 12")
    expect(audios.map(\.audioSeq).sorted() == [1, 2], "both PCM audio packets delivered intact")

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

    // Verify full 6-probe ceiling (~150ms spacing) when sender never replies
    let silentEpoch: Int64 = 304
    let silentSecret = UDPMediaKeyMaterial.generateRootSecret()
    let silentKeys = try UDPMediaKeyMaterial.derive(rootSecret: silentSecret, sessionEpoch: silentEpoch)
    var silentCrypto = UDPMediaCryptoSession(keyMaterial: silentKeys)
    let sixProbesSem = DispatchSemaphore(value: 0)
    var silentArrivalUptimes: [TimeInterval] = []
    guard let silentServer = NonBlockingUDPSocket(
        preferIPv6: false,
        boundInterfaceName: "lo0",
        queue: probeQueue,
        onReceive: { data, _ in
            guard let pkt = try? silentCrypto.open(datagram: data, expectedDirection: .receiverToSender),
                  pkt.header.packetType == .probe else { return }
            lock.lock()
            silentArrivalUptimes.append(ProcessInfo.processInfo.systemUptime)
            let count = silentArrivalUptimes.count
            lock.unlock()
            if count == UDPMediaReceiverSession.maxInitialProbes {
                sixProbesSem.signal()
            }
        }
    ) else {
        fatalError("Failed to open silent probe server socket")
    }
    defer { silentServer.close() }
    let silentConfig = UDPMediaConfigMessage(
        sessionEpoch: silentEpoch,
        udpPort: silentServer.localPort,
        rootSecret: silentSecret
    )
    guard let silentReceiver = UDPMediaReceiverSession(
        config: silentConfig,
        generation: 8,
        senderHost: "127.0.0.1",
        boundInterfaceName: "lo0"
    ) else {
        fatalError("Failed to create silent receiver")
    }
    defer { silentReceiver.stop() }
    expect(sixProbesSem.wait(timeout: .now() + 2.0) == .success,
           "UDPMediaReceiverSession must emit all 6 initial UDP probes (~150ms spacing)")
    Thread.sleep(forTimeInterval: 0.25)
    lock.lock()
    let silentCount = silentArrivalUptimes.count
    let totalSpan = (silentArrivalUptimes.last ?? 0) - (silentArrivalUptimes.first ?? 0)
    lock.unlock()
    expect(silentCount == 6, "UDPMediaReceiverSession must stop at 6 initial probes (got \(silentCount))")
    expect(totalSpan >= 0.60, "6 probes spaced by 150ms must span >= 600ms (got \(totalSpan)s)")
}

private func runSocketWouldBlockAndBytesSentAccountingCheck() {
    let lock = NSLock()
    let readySem = DispatchSemaphore(value: 0)
    let doneSem = DispatchSemaphore(value: 0)

    guard let sender = UDPMediaSenderSession(
        sessionEpoch: 404,
        wireGeneration: 9,
        initialBitrate: 50_000_000,
        bitrateBounds: 10_000_000...100_000_000,
        peerHost: "127.0.0.1",
        peerPort: nil,
        boundInterfaceName: "lo0"
    ) else {
        fatalError("Failed to create sender for bytes-sent accounting check")
    }
    defer { sender.stop() }
    sender.onReady = { _, _ in readySem.signal() }

    guard let receiver = UDPMediaReceiverSession(
        config: sender.makeConfigMessage(),
        generation: 9,
        senderHost: "127.0.0.1",
        boundInterfaceName: "lo0"
    ) else {
        fatalError("Failed to create receiver for bytes-sent accounting check")
    }
    defer { receiver.stop() }
    sender.configurePeer(host: "127.0.0.1", port: receiver.localPort)
    expect(readySem.wait(timeout: .now() + 2.0) == .success, "UDP handshake ready for accounting check")

    // Inject EAGAIN/EWOULDBLOCK (.wouldBlock) on the first fragment of Frame #1 (multi-fragment payload),
    // and let remaining fragments succeed; then send a single-fragment Frame #2 where all packets succeed.
    var callIndex = 0
    var actualWireBytesAccepted = 0
    var reportedBytesTotal = 0
    var completedFrameReports: [Bool] = []

    sender.queue.sync {
        sender.onBytesSent = { bytes, completed in
            lock.lock()
            reportedBytesTotal += bytes
            completedFrameReports.append(completed)
            if completed {
                doneSem.signal()
            }
            lock.unlock()
        }
        sender.socketSendOverride = { data, _ in
            lock.lock()
            let current = callIndex
            callIndex += 1
            if current == 0 {
                lock.unlock()
                return .wouldBlock
            }
            actualWireBytesAccepted += data.count
            lock.unlock()
            return .sent(data.count)
        }
    }

    // Multi-fragment frame (~3.6 KB -> 4 data shards + FEC parity): shard 0 hits .wouldBlock!
    let multiFragFrame = Data([0x00, 0x00, 0x00, 0x01, 0x65]) + Data(repeating: 0xAB, count: 3600)
    expect(sender.sendFrame(annexB: multiFragFrame, isKeyframe: true, captureTimestampMs: 500, configVersion: 1),
           "multi-fragment frame enqueued")
    Thread.sleep(forTimeInterval: 0.05)

    lock.lock()
    let completedAfterDroppedFirstFrag = completedFrameReports.contains(true)
    let bytesAfterFirstFrame = reportedBytesTotal
    let acceptedAfterFirstFrame = actualWireBytesAccepted
    lock.unlock()
    expect(!completedAfterDroppedFirstFrag,
           "frame with a .wouldBlock dropped fragment must NEVER report completedFrame == true")
    expect(bytesAfterFirstFrame == acceptedAfterFirstFrame,
           "onBytesSent must NEVER count .wouldBlock dropped packet bytes (\(bytesAfterFirstFrame) vs \(acceptedAfterFirstFrame))")

    // Second frame: all fragments succeed -> reports exact wire bytes and completedFrame == true
    let smallFrame = Data([0x00, 0x00, 0x00, 0x01, 0x41, 0x9A, 0x22, 0x33])
    expect(sender.sendFrame(annexB: smallFrame, isKeyframe: false, captureTimestampMs: 516, configVersion: 1),
           "second frame enqueued")
    expect(doneSem.wait(timeout: .now() + 1.0) == .success, "complete second frame reported")
    Thread.sleep(forTimeInterval: 0.02)

    lock.lock()
    let finalReported = reportedBytesTotal
    let finalAccepted = actualWireBytesAccepted
    let completedTrueCount = completedFrameReports.filter { $0 }.count
    lock.unlock()
    expect(finalReported == finalAccepted,
           "total onBytesSent (\(finalReported)) must equal exact accepted socket bytes (\(finalAccepted))")
    expect(completedTrueCount == 1,
           "only the fully transmitted frame may report completedFrame == true (got \(completedTrueCount))")
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
        expect(v4OnlySock.sendStatus(Data(), to: v4Dest) == .failed,
               "empty datagram sendStatus must return .failed")
        v4OnlySock.close()
        expect(v4OnlySock.sendStatus(Data([0x01]), to: v4Dest) == .failed && !v4OnlySock.send(Data([0x01]), to: v4Dest),
               "closed NonBlockingUDPSocket.sendStatus/send must return .failed/false")

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

        // 4. Receiver multi-probe retry (~150ms spacing, up to 6 probes)
        try runReceiverProbeRetryCheck()

        // 5. EAGAIN/EWOULDBLOCK (.wouldBlock) packet-drop accounting in onBytesSent
        runSocketWouldBlockAndBytesSentAccountingCheck()

        print("UDPMediaTransportSelfTest PASS")
    }
}

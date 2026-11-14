import Darwin
import Foundation
import Network

/// Extracts the literal IPv4/IPv6 host string from an `NWEndpoint` when available.
enum UDPEndpointResolver {
    static func hostString(from endpoint: NWEndpoint?) -> String? {
        guard let endpoint else { return nil }
        switch endpoint {
        case .hostPort(let host, _):
            return cleanHost(host.debugDescription)
        default:
            return nil
        }
    }

    static func cleanHost(_ raw: String) -> String? {
        var trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("[") && trimmed.hasSuffix("]") {
            trimmed = String(trimmed.dropFirst().dropLast())
        }
        // Strip interface scope ID (e.g. %en0) for numeric parsing if needed, or keep for getaddrinfo
        guard !trimmed.isEmpty else { return nil }
        return trimmed
    }

    static func resolveSockAddr(host: String, port: UInt16) -> sockaddr_storage? {
        guard let cleaned = cleanHost(host), port > 0 else { return nil }
        var hints = addrinfo()
        hints.ai_family = AF_UNSPEC
        hints.ai_socktype = SOCK_DGRAM
        hints.ai_protocol = IPPROTO_UDP
        hints.ai_flags = AI_NUMERICHOST | AI_NUMERICSERV
        var res: UnsafeMutablePointer<addrinfo>?
        let status = getaddrinfo(cleaned, String(port), &hints, &res)
        if status != 0 {
            hints.ai_flags = AI_NUMERICSERV
            guard getaddrinfo(cleaned, String(port), &hints, &res) == 0 else {
                return nil
            }
        }
        defer { if let res { freeaddrinfo(res) } }
        guard let info = res, let addr = info.pointee.ai_addr else { return nil }
        var storage = sockaddr_storage()
        memcpy(&storage, addr, Int(info.pointee.ai_addrlen))
        return storage
    }

    static func sockAddrLength(_ storage: sockaddr_storage) -> socklen_t {
        switch Int32(storage.ss_family) {
        case AF_INET:
            return socklen_t(MemoryLayout<sockaddr_in>.size)
        case AF_INET6:
            return socklen_t(MemoryLayout<sockaddr_in6>.size)
        default:
            return socklen_t(storage.ss_len)
        }
    }
}

/// Non-blocking POSIX UDP socket wrapper managed on a dedicated serial `DispatchQueue`.
final class NonBlockingUDPSocket: @unchecked Sendable {
    let fd: Int32
    let localPort: UInt16
    let family: Int32
    private var readSource: DispatchSourceRead?
    private var closed = false

    init?(preferIPv6: Bool = false, queue: DispatchQueue, onReceive: @escaping (Data, sockaddr_storage) -> Void) {
        let sockFamily: Int32 = preferIPv6 ? AF_INET6 : AF_INET
        let sock = Darwin.socket(sockFamily, SOCK_DGRAM, IPPROTO_UDP)
        guard sock >= 0 else { return nil }

        let flags = fcntl(sock, F_GETFL, 0)
        _ = fcntl(sock, F_SETFL, flags | O_NONBLOCK)
        var noSigPipe: Int32 = 1
        _ = setsockopt(sock, SOL_SOCKET, SO_NOSIGPIPE, &noSigPipe, socklen_t(MemoryLayout<Int32>.size))
        var sndBuf: Int32 = 512 * 1024
        _ = setsockopt(sock, SOL_SOCKET, SO_SNDBUF, &sndBuf, socklen_t(MemoryLayout<Int32>.size))
        var rcvBuf: Int32 = 1024 * 1024
        _ = setsockopt(sock, SOL_SOCKET, SO_RCVBUF, &rcvBuf, socklen_t(MemoryLayout<Int32>.size))

        var boundPort: UInt16 = 0
        if sockFamily == AF_INET6 {
            var v6Only: Int32 = 0
            _ = setsockopt(sock, IPPROTO_IPV6, IPV6_V6ONLY, &v6Only, socklen_t(MemoryLayout<Int32>.size))
            var addr6 = sockaddr_in6()
            addr6.sin6_len = UInt8(MemoryLayout<sockaddr_in6>.size)
            addr6.sin6_family = sa_family_t(AF_INET6)
            addr6.sin6_port = 0
            addr6.sin6_addr = in6addr_any
            let bindRes = withUnsafePointer(to: &addr6) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    Darwin.bind(sock, $0, socklen_t(MemoryLayout<sockaddr_in6>.size))
                }
            }
            guard bindRes == 0 else {
                Darwin.close(sock)
                return nil
            }
            var name = sockaddr_in6()
            var len = socklen_t(MemoryLayout<sockaddr_in6>.size)
            _ = withUnsafeMutablePointer(to: &name) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    getsockname(sock, $0, &len)
                }
            }
            boundPort = UInt16(bigEndian: name.sin6_port)
        } else {
            var addr4 = sockaddr_in()
            addr4.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
            addr4.sin_family = sa_family_t(AF_INET)
            addr4.sin_port = 0
            addr4.sin_addr.s_addr = INADDR_ANY.bigEndian
            let bindRes = withUnsafePointer(to: &addr4) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    Darwin.bind(sock, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
            guard bindRes == 0 else {
                Darwin.close(sock)
                return nil
            }
            var name = sockaddr_in()
            var len = socklen_t(MemoryLayout<sockaddr_in>.size)
            _ = withUnsafeMutablePointer(to: &name) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    getsockname(sock, $0, &len)
                }
            }
            boundPort = UInt16(bigEndian: name.sin_port)
        }

        self.fd = sock
        self.localPort = boundPort
        self.family = sockFamily

        let source = DispatchSource.makeReadSource(fileDescriptor: sock, queue: queue)
        source.setEventHandler { [weak self] in
            guard let self, !self.closed else { return }
            var buffer = [UInt8](repeating: 0, count: UDPMediaHeader.maxDatagramLength + 64)
            for _ in 0..<64 {
                var peer = sockaddr_storage()
                var peerLen = socklen_t(MemoryLayout<sockaddr_storage>.size)
                let readBytes = withUnsafeMutablePointer(to: &peer) { peerPtr in
                    peerPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { saPtr in
                        Darwin.recvfrom(self.fd, &buffer, buffer.count, 0, saPtr, &peerLen)
                    }
                }
                if readBytes > 0 {
                    onReceive(Data(buffer.prefix(readBytes)), peer)
                } else {
                    break
                }
            }
        }
        source.setCancelHandler {
            Darwin.close(sock)
        }
        self.readSource = source
        source.resume()
    }

    @discardableResult
    func send(_ data: Data, to destination: sockaddr_storage) -> Bool {
        guard !closed else { return false }
        var dest = destination
        let addrLen = UDPEndpointResolver.sockAddrLength(dest)
        return data.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return false }
            let sent = withUnsafePointer(to: &dest) { destPtr in
                destPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { saPtr in
                    Darwin.sendto(fd, base, data.count, 0, saPtr, addrLen)
                }
            }
            if sent == data.count {
                return true
            }
            let err = errno
            return err == EAGAIN || err == EWOULDBLOCK
        }
    }

    func close() {
        guard !closed else { return }
        closed = true
        readSource?.cancel()
        readSource = nil
    }
}

/// Sender-side UDP media session managing probe handshake, debt-based pacing,
/// FEC encoding, NACK retransmission, delay-gradient BWE, and TCP fallback.
final class UDPMediaSenderSession: @unchecked Sendable {
    static let feedbackSilenceTimeoutSeconds: TimeInterval = 2.5
    static let pacerTickInterval: DispatchTimeInterval = .milliseconds(1)

    let sessionEpoch: Int64
    let wireGeneration: UInt64
    let rootSecret: Data
    let queue: DispatchQueue

    private var crypto: UDPMediaCryptoSession
    private var pacer: UDPDebtPacer
    private var rtxCache = UDPRetransmitCache()
    private(set) var bwe: UDPDelayGradientBWE
    private var socket: NonBlockingUDPSocket?
    private var pacerTimer: DispatchSourceTimer?
    private var peerAddress: sockaddr_storage?

    private let stateLock = NSLock()
    private var _isReady = false
    private var _stopped = false
    private var _localPort: UInt16 = 0
    private var lastReceiverActivityUptime: TimeInterval = 0
    private var lastFrameSentUptime: TimeInterval = 0
    private var nextFrameId: UInt32 = 1

    var onReady: ((UInt64, Int64) -> Void)?
    var onBandwidthDecision: ((UInt64, Int64, UDPBandwidthDecision, Int) -> Void)?
    var onKeyframeRequested: ((UInt64, Int64) -> Void)?
    var onFallbackToTCP: ((UInt64, Int64, String) -> Void)?
    var onBytesSent: ((Int, Bool) -> Void)?

    var isReady: Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return _isReady && !_stopped
    }

    var localPort: UInt16 {
        stateLock.lock()
        defer { stateLock.unlock() }
        return _localPort
    }

    init?(
        sessionEpoch: Int64,
        wireGeneration: UInt64,
        initialBitrate: Int,
        bitrateBounds: ClosedRange<Int>,
        peerHost: String?,
        peerPort: UInt16?
    ) {
        let secret = UDPMediaKeyMaterial.generateRootSecret()
        guard let keyMaterial = try? UDPMediaKeyMaterial.derive(rootSecret: secret, sessionEpoch: sessionEpoch) else {
            return nil
        }
        self.sessionEpoch = sessionEpoch
        self.wireGeneration = wireGeneration
        self.rootSecret = secret
        self.queue = DispatchQueue(label: "app.displayweave.udp.sender.\(sessionEpoch)", qos: .userInteractive)
        self.crypto = UDPMediaCryptoSession(keyMaterial: keyMaterial)
        self.pacer = UDPDebtPacer(targetBitrateBps: initialBitrate)
        self.bwe = UDPDelayGradientBWE(initialBitrate: initialBitrate, bounds: bitrateBounds)

        var resolvedPeer: sockaddr_storage?
        if let peerHost, let peerPort, peerPort > 0 {
            resolvedPeer = UDPEndpointResolver.resolveSockAddr(host: peerHost, port: peerPort)
        }
        self.peerAddress = resolvedPeer
        let preferIPv6 = resolvedPeer.map { Int32($0.ss_family) == AF_INET6 } ?? false

        guard let boundSocket = NonBlockingUDPSocket(
            preferIPv6: preferIPv6,
            queue: queue,
            onReceive: { [weak self] data, addr in
                self?.handleIncomingDatagram(data, from: addr)
            }
        ) else {
            return nil
        }
        self.socket = boundSocket
        self._localPort = boundSocket.localPort

        let timer = DispatchSource.makeTimerSource(flags: .strict, queue: queue)
        timer.schedule(deadline: .now() + Self.pacerTickInterval, repeating: Self.pacerTickInterval)
        timer.setEventHandler { [weak self] in
            self?.tickPacer()
        }
        self.pacerTimer = timer
        timer.resume()
    }

    func makeConfigMessage() -> UDPMediaConfigMessage {
        UDPMediaConfigMessage(
            sessionEpoch: sessionEpoch,
            udpPort: localPort,
            rootSecret: rootSecret
        )
    }

    func configurePeer(host: String, port: UInt16) {
        queue.async { [weak self] in
            guard let self, !self.isStoppedInternal else { return }
            if let addr = UDPEndpointResolver.resolveSockAddr(host: host, port: port) {
                self.peerAddress = addr
                self.sendProbeOnQueue(isAck: false)
            }
        }
    }

    func updateTargetBitrate(_ bitrateBps: Int) {
        queue.async { [weak self] in
            guard let self, !self.isStoppedInternal else { return }
            self.pacer.updateTargetBitrate(bitrateBps)
        }
    }

    /// Enqueues an encoded Annex-B frame onto the UDP media plane when ready.
    /// Returns `false` if the UDP session is not yet ready or has fallen back to TCP.
    func sendFrame(
        annexB: Data,
        isKeyframe: Bool,
        captureTimestampMs: Int64,
        configVersion: Int64
    ) -> Bool {
        guard isReady else { return false }
        queue.async { [weak self] in
            guard let self, !self.isStoppedInternal, self.peerAddress != nil else { return }
            self.enqueueFrameOnQueue(
                annexB: annexB,
                isKeyframe: isKeyframe,
                captureTimestampMs: captureTimestampMs,
                configVersion: configVersion
            )
        }
        return true
    }

    func stop() {
        stateLock.lock()
        let alreadyStopped = _stopped
        _stopped = true
        _isReady = false
        stateLock.unlock()
        guard !alreadyStopped else { return }
        queue.async { [weak self] in
            guard let self else { return }
            self.pacerTimer?.cancel()
            self.pacerTimer = nil
            self.socket?.close()
            self.socket = nil
        }
    }

    private var isStoppedInternal: Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return _stopped
    }

    private static func currentSendTimeUs() -> UInt32 {
        let uptimeUs = UInt64(ProcessInfo.processInfo.systemUptime * 1_000_000)
        return UInt32(truncatingIfNeeded: uptimeUs)
    }

    private func sendProbeOnQueue(isAck: Bool) {
        guard let dest = peerAddress, let socket else { return }
        let flags: UDPMediaFlags = isAck ? [.probeAck] : []
        let probePayload = Data("DWV1-PROBE".utf8)
        guard let (datagram, _, _) = try? crypto.seal(
            direction: .senderToReceiver,
            packetType: .probe,
            flags: flags,
            sendTimeUs: Self.currentSendTimeUs(),
            frameId: 0,
            fragIndex: 0,
            fragCount: 1,
            payload: probePayload
        ) else { return }
        _ = socket.send(datagram, to: dest)
    }

    private func enqueueFrameOnQueue(
        annexB: Data,
        isKeyframe: Bool,
        captureTimestampMs: Int64,
        configVersion: Int64
    ) {
        guard let dataShards = try? UDPMediaFramePacketizer.makeDataFragments(
            annexB: annexB,
            captureTimestampMs: captureTimestampMs,
            configVersion: configVersion
        ) else { return }

        let frameId = nextFrameId
        nextFrameId &+= 1
        let nowUptime = ProcessInfo.processInfo.systemUptime
        lastFrameSentUptime = nowUptime
        let sendTimeUs = Self.currentSendTimeUs()
        let fragCount = UInt16(dataShards.count)
        var queuedDatagrams: [UDPQueuedDatagram] = []
        queuedDatagrams.reserveCapacity(dataShards.count + 4)

        for (index, shard) in dataShards.enumerated() {
            var flags: UDPMediaFlags = isKeyframe ? [.keyframe] : []
            if index == dataShards.count - 1 {
                flags.insert(.endOfFrame)
            }
            guard let (datagram, _, _) = try? crypto.seal(
                direction: .senderToReceiver,
                packetType: .videoData,
                flags: flags,
                sendTimeUs: sendTimeUs,
                frameId: frameId,
                fragIndex: UInt16(index),
                fragCount: fragCount,
                payload: shard
            ) else { continue }

            rtxCache.store(
                frameId: frameId,
                fragIndex: UInt16(index),
                fragCount: fragCount,
                flags: flags,
                payload: shard,
                nowUptime: nowUptime
            )
            queuedDatagrams.append(
                UDPQueuedDatagram(
                    priority: isKeyframe ? .keyframe : .normalVideo,
                    frameId: frameId,
                    fragIndex: UInt16(index),
                    isParity: false,
                    datagram: datagram
                )
            )
        }

        let parityShards = UDPMediaFECEncoder.encodeParityShards(
            dataShards: dataShards,
            lossFraction: bwe.latestLossFraction,
            isKeyframe: isKeyframe
        )
        for parity in parityShards {
            let flags: UDPMediaFlags = isKeyframe ? [.keyframe] : []
            guard let (datagram, _, _) = try? crypto.seal(
                direction: .senderToReceiver,
                packetType: .videoParity,
                flags: flags,
                sendTimeUs: sendTimeUs,
                frameId: frameId,
                fragIndex: parity.descriptor.encodedFragIndex,
                fragCount: parity.descriptor.encodedFragCount,
                payload: parity.payload
            ) else { continue }
            queuedDatagrams.append(
                UDPQueuedDatagram(
                    priority: .fecParity,
                    frameId: frameId,
                    fragIndex: parity.descriptor.encodedFragIndex,
                    isParity: true,
                    datagram: datagram
                )
            )
        }

        pacer.enqueueFrameDatagrams(queuedDatagrams, isKeyframe: isKeyframe, frameId: frameId)
        flushPacerBurstOnQueue(nowUptime: nowUptime)
    }

    private func tickPacer() {
        guard !isStoppedInternal else { return }
        let now = ProcessInfo.processInfo.systemUptime
        if isReady,
           lastFrameSentUptime > 0,
           lastReceiverActivityUptime > 0,
           now - lastFrameSentUptime < 0.5,
           now - lastReceiverActivityUptime > Self.feedbackSilenceTimeoutSeconds {
            stateLock.lock()
            _isReady = false
            stateLock.unlock()
            onFallbackToTCP?(wireGeneration, sessionEpoch, "udp-feedback-timeout")
            return
        }
        flushPacerBurstOnQueue(nowUptime: now)
    }

    private func flushPacerBurstOnQueue(nowUptime: TimeInterval) {
        guard let dest = peerAddress, let socket else { return }
        let burst = pacer.pollTransmitBurst(nowUptime: nowUptime)
        guard !burst.isEmpty else { return }
        var totalBytes = 0
        var completedFrame = false
        for item in burst {
            if socket.send(item.datagram, to: dest) {
                totalBytes += item.datagram.count
                if !item.isParity {
                    completedFrame = true
                }
            }
        }
        if totalBytes > 0 {
            onBytesSent?(totalBytes, completedFrame)
        }
    }

    private func handleIncomingDatagram(_ datagram: Data, from sourceAddr: sockaddr_storage) {
        guard !isStoppedInternal else { return }
        guard let packet = try? crypto.open(datagram: datagram, expectedDirection: .receiverToSender) else {
            return
        }
        let now = ProcessInfo.processInfo.systemUptime
        lastReceiverActivityUptime = now
        peerAddress = sourceAddr

        var becameReady = false
        stateLock.lock()
        if !_isReady && !_stopped {
            _isReady = true
            becameReady = true
        }
        stateLock.unlock()
        if becameReady {
            sendProbeOnQueue(isAck: true)
            onReady?(wireGeneration, sessionEpoch)
        }

        switch packet.header.packetType {
        case .probe:
            if !packet.header.flags.contains(.probeAck) {
                sendProbeOnQueue(isAck: true)
            }
        case .nack:
            guard let nack = try? UDPMediaNackPayload.decode(from: packet.payload) else { return }
            let entries = rtxCache.consumeForRetransmit(nack: nack, nowUptime: now)
            let sendTimeUs = Self.currentSendTimeUs()
            for entry in entries {
                var flags = entry.flags
                flags.insert(.retransmit)
                guard let (rtxDatagram, _, _) = try? crypto.seal(
                    direction: .senderToReceiver,
                    packetType: .videoData,
                    flags: flags,
                    sendTimeUs: sendTimeUs,
                    frameId: entry.frameId,
                    fragIndex: entry.fragIndex,
                    fragCount: entry.fragCount,
                    payload: entry.payload
                ) else { continue }
                pacer.enqueueRetransmit(
                    UDPQueuedDatagram(
                        priority: .retransmit,
                        frameId: entry.frameId,
                        fragIndex: entry.fragIndex,
                        isParity: false,
                        datagram: rtxDatagram
                    )
                )
            }
            flushPacerBurstOnQueue(nowUptime: now)

        case .feedback:
            guard let feedback = try? UDPMediaFeedbackPayload.decode(from: packet.payload) else { return }
            if let decision = bwe.ingestFeedback(
                feedback,
                nowUptime: now,
                nowSendTimeUs: Self.currentSendTimeUs()
            ) {
                let effectiveEncoderBps = bwe.effectiveEncoderBitrate()
                pacer.updateTargetBitrate(bwe.currentBitrate)
                onBandwidthDecision?(wireGeneration, sessionEpoch, decision, effectiveEncoderBps)
            }

        default:
            break
        }
    }
}

/// Receiver-side UDP media session managing probe response, per-packet AES-128-GCM
/// verification, bounded reassembly, FEC recovery, NACK emission, jitter buffering,
/// and 30ms BWE feedback.
final class UDPMediaReceiverSession: @unchecked Sendable {
    static let maintenanceInterval: DispatchTimeInterval = .milliseconds(5)

    let sessionEpoch: Int64
    let generation: UInt64
    let queue: DispatchQueue

    private var crypto: UDPMediaCryptoSession
    private var reassembler = UDPMediaReassembler()
    private var jitterBuffer = UDPJitterBuffer()
    private var arrivalEstimator = UDPReceiverArrivalEstimator()
    private var socket: NonBlockingUDPSocket?
    private var timer: DispatchSourceTimer?
    private var senderAddress: sockaddr_storage?
    private var stopped = false
    private(set) var localPort: UInt16 = 0
    private var currentRttUs: UInt32 = 10_000
    private var currentDecodeQueueMs: UInt16 = 0
    private var currentRenderFps: UInt16 = 60

    var onFrameReady: ((UInt64, UDPMediaFrameEnvelope) -> Void)?
    var onKeyframeNeeded: ((UInt64, String) -> Void)?

    init?(
        config: UDPMediaConfigMessage,
        generation: UInt64,
        senderHost: String?
    ) {
        guard let secret = config.rootSecretData,
              let keyMaterial = try? UDPMediaKeyMaterial.derive(
                rootSecret: secret,
                sessionEpoch: config.sessionEpoch
              ) else {
            return nil
        }
        self.sessionEpoch = config.sessionEpoch
        self.generation = generation
        self.queue = DispatchQueue(label: "app.displayweave.udp.receiver.\(config.sessionEpoch)", qos: .userInteractive)
        self.crypto = UDPMediaCryptoSession(keyMaterial: keyMaterial)

        if let senderHost, config.udpPort > 0 {
            self.senderAddress = UDPEndpointResolver.resolveSockAddr(host: senderHost, port: config.udpPort)
        }
        let preferIPv6 = self.senderAddress.map { Int32($0.ss_family) == AF_INET6 } ?? false

        guard let boundSocket = NonBlockingUDPSocket(
            preferIPv6: preferIPv6,
            queue: queue,
            onReceive: { [weak self] data, addr in
                self?.handleIncomingDatagram(data, from: addr)
            }
        ) else {
            return nil
        }
        self.socket = boundSocket
        self.localPort = boundSocket.localPort

        let maintenanceTimer = DispatchSource.makeTimerSource(flags: .strict, queue: queue)
        maintenanceTimer.schedule(deadline: .now() + Self.maintenanceInterval, repeating: Self.maintenanceInterval)
        maintenanceTimer.setEventHandler { [weak self] in
            self?.runMaintenanceOnQueue()
        }
        self.timer = maintenanceTimer
        maintenanceTimer.resume()

        queue.async { [weak self] in
            self?.sendProbeOnQueue(isAck: false)
        }
    }

    func updateReceiverTelemetry(rttMs: Double, decodeQueueMs: Int, renderFps: Int) {
        queue.async { [weak self] in
            guard let self, !self.stopped else { return }
            if rttMs.isFinite && rttMs > 0 {
                self.currentRttUs = UInt32(min(500_000, max(1_000, Int(rttMs * 1_000))))
            }
            self.currentDecodeQueueMs = UInt16(clamping: max(0, decodeQueueMs))
            self.currentRenderFps = UInt16(clamping: max(0, renderFps))
        }
    }

    func stop() {
        queue.async { [weak self] in
            guard let self, !self.stopped else { return }
            self.stopped = true
            self.timer?.cancel()
            self.timer = nil
            self.socket?.close()
            self.socket = nil
            self.jitterBuffer.reset()
        }
    }

    private static func nowMonoNs() -> UInt64 {
        UInt64(ProcessInfo.processInfo.systemUptime * 1_000_000_000)
    }

    private static func nowSendTimeUs() -> UInt32 {
        UInt32(truncatingIfNeeded: UInt64(ProcessInfo.processInfo.systemUptime * 1_000_000))
    }

    private func sendProbeOnQueue(isAck: Bool) {
        guard let dest = senderAddress, let socket else { return }
        let flags: UDPMediaFlags = isAck ? [.probeAck] : []
        guard let (datagram, _, _) = try? crypto.seal(
            direction: .receiverToSender,
            packetType: .probe,
            flags: flags,
            sendTimeUs: Self.nowSendTimeUs(),
            frameId: 0,
            fragIndex: 0,
            fragCount: 1,
            payload: Data("DWV1-RCV-PROBE".utf8)
        ) else { return }
        _ = socket.send(datagram, to: dest)
    }

    private func handleIncomingDatagram(_ datagram: Data, from sourceAddr: sockaddr_storage) {
        guard !stopped else { return }
        guard let packet = try? crypto.open(datagram: datagram, expectedDirection: .senderToReceiver) else {
            return
        }
        senderAddress = sourceAddr
        let monoNs = Self.nowMonoNs()

        if packet.header.packetType == .probe {
            if !packet.header.flags.contains(.probeAck) {
                sendProbeOnQueue(isAck: true)
            }
            return
        }

        arrivalEstimator.recordPacket(
            extendedSequence: packet.extendedSequence,
            sendTimeUs: packet.header.sendTimeUs,
            arrivalMonoNs: monoNs
        )

        if let assembled = reassembler.ingest(packet: packet, nowMonoNs: monoNs) {
            let result = jitterBuffer.insert(assembled, nowMonoNs: monoNs)
            for frame in result.deliverable {
                onFrameReady?(generation, frame)
            }
            if result.needsKeyframe || reassembler.consumeKeyframeRequestFlag() {
                onKeyframeNeeded?(generation, "udp-jitter-or-loss")
            }
        } else if reassembler.consumeKeyframeRequestFlag() {
            onKeyframeNeeded?(generation, "udp-reassembly-expired")
        }

        emitFeedbackIfDue(nowMonoNs: monoNs)
    }

    private func runMaintenanceOnQueue() {
        guard !stopped else { return }
        let monoNs = Self.nowMonoNs()
        let nacks = reassembler.pollNacks(nowMonoNs: monoNs, rttUs: currentRttUs)
        if let dest = senderAddress, let socket {
            for nack in nacks {
                if let (dg, _, _) = try? crypto.seal(
                    direction: .receiverToSender,
                    packetType: .nack,
                    flags: [],
                    sendTimeUs: Self.nowSendTimeUs(),
                    frameId: nack.frameId,
                    fragIndex: nack.baseFragIndex,
                    fragCount: nack.missingCount,
                    payload: nack.encode()
                ) {
                    _ = socket.send(dg, to: dest)
                }
            }
        }
        let polled = jitterBuffer.pollDeliverable(nowMonoNs: monoNs)
        for frame in polled.deliverable {
            onFrameReady?(generation, frame)
        }
        if polled.needsKeyframe || reassembler.consumeKeyframeRequestFlag() {
            onKeyframeNeeded?(generation, "udp-maintenance-recovery")
        }
        emitFeedbackIfDue(nowMonoNs: monoNs)
    }

    private func emitFeedbackIfDue(nowMonoNs: UInt64) {
        guard let dest = senderAddress,
              let socket,
              let feedback = arrivalEstimator.pollFeedbackIfDue(
                nowMonoNs: nowMonoNs,
                decodeQueueMs: currentDecodeQueueMs,
                renderFps: currentRenderFps
              ) else { return }
        if let (dg, _, _) = try? crypto.seal(
            direction: .receiverToSender,
            packetType: .feedback,
            flags: [],
            sendTimeUs: Self.nowSendTimeUs(),
            frameId: UInt32(truncatingIfNeeded: feedback.highestSeq),
            fragIndex: 0,
            fragCount: 1,
            payload: feedback.encode()
        ) {
            _ = socket.send(dg, to: dest)
        }
    }
}

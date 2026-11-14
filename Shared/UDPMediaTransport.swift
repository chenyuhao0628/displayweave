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

    /// Determines whether an unbound or pre-peer-port UDP socket should open as `AF_INET6`
    /// (with `IPV6_V6ONLY = 0` dual-stack support). When `host` is `nil`, defaults to
    /// dual-stack `AF_INET6` so both IPv4 (`127.0.0.1` / LAN) and IPv6 (`::1` / `fe80::...%enX`)
    /// peers can reach the socket cleanly.
    static func prefersIPv6(host: String?) -> Bool {
        guard let rawHost = host, let cleaned = cleanHost(rawHost) else {
            return true
        }
        if cleaned.contains(":") {
            return true
        }
        if let resolved = resolveSockAddr(host: cleaned, port: 1) {
            return Int32(resolved.ss_family) == AF_INET6
        }
        return false
    }

    /// Adapts `destination` to match `socketFamily` on Darwin, converting `AF_INET`
    /// destinations into IPv4-mapped `::ffff:x.x.x.x` `sockaddr_in6` addresses for
    /// dual-stack `AF_INET6` sockets (and unwrapping mapped addresses for `AF_INET` sockets).
    static func adaptSockAddr(_ destination: sockaddr_storage, forSocketFamily socketFamily: Int32) -> sockaddr_storage? {
        let destFamily = Int32(destination.ss_family)
        if destFamily == socketFamily {
            return destination
        }
        if socketFamily == AF_INET6 && destFamily == AF_INET {
            var v4 = destination
            let addrIn = withUnsafePointer(to: &v4) {
                $0.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee }
            }
            var addr6 = sockaddr_in6()
            addr6.sin6_len = UInt8(MemoryLayout<sockaddr_in6>.size)
            addr6.sin6_family = sa_family_t(AF_INET6)
            addr6.sin6_port = addrIn.sin_port
            let v4Bytes = withUnsafeBytes(of: addrIn.sin_addr.s_addr) { Array($0) }
            withUnsafeMutableBytes(of: &addr6.sin6_addr) { raw in
                for i in 0..<10 { raw[i] = 0 }
                raw[10] = 0xFF
                raw[11] = 0xFF
                raw[12] = v4Bytes[0]
                raw[13] = v4Bytes[1]
                raw[14] = v4Bytes[2]
                raw[15] = v4Bytes[3]
            }
            var out = sockaddr_storage()
            _ = withUnsafePointer(to: &addr6) { src in
                memcpy(&out, src, MemoryLayout<sockaddr_in6>.size)
            }
            return out
        }
        if socketFamily == AF_INET && destFamily == AF_INET6 {
            var v6 = destination
            let addrIn6 = withUnsafePointer(to: &v6) {
                $0.withMemoryRebound(to: sockaddr_in6.self, capacity: 1) { $0.pointee }
            }
            let bytes = withUnsafeBytes(of: addrIn6.sin6_addr) { Array($0) }
            guard bytes.count == 16,
                  bytes[0..<10].allSatisfy({ $0 == 0 }),
                  bytes[10] == 0xFF,
                  bytes[11] == 0xFF else {
                return nil
            }
            var addr4 = sockaddr_in()
            addr4.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
            addr4.sin_family = sa_family_t(AF_INET)
            addr4.sin_port = addrIn6.sin6_port
            withUnsafeMutableBytes(of: &addr4.sin_addr.s_addr) { dst in
                dst[0] = bytes[12]
                dst[1] = bytes[13]
                dst[2] = bytes[14]
                dst[3] = bytes[15]
            }
            var out = sockaddr_storage()
            _ = withUnsafePointer(to: &addr4) { src in
                memcpy(&out, src, MemoryLayout<sockaddr_in>.size)
            }
            return out
        }
        return nil
    }
}

/// Non-blocking POSIX UDP socket wrapper managed on a dedicated serial `DispatchQueue`.
final class NonBlockingUDPSocket: @unchecked Sendable {
    let fd: Int32
    let localPort: UInt16
    let family: Int32
    let boundInterfaceIndex: UInt32
    private let closeLock = NSLock()
    private var readSource: DispatchSourceRead?
    private var closed = false

    init?(
        preferIPv6: Bool = false,
        boundInterfaceName: String? = nil,
        queue: DispatchQueue,
        onReceive: @escaping (Data, sockaddr_storage) -> Void
    ) {
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

        var resolvedIfIndex: UInt32 = 0
        if let rawIfName = boundInterfaceName?.trimmingCharacters(in: .whitespacesAndNewlines),
           !rawIfName.isEmpty {
            let idx = if_nametoindex(rawIfName)
            guard idx > 0 else {
                Darwin.close(sock)
                return nil
            }
            var mutableIdx = idx
            let bindIfResult: Int32
            if sockFamily == AF_INET6 {
                bindIfResult = setsockopt(
                    sock,
                    IPPROTO_IPV6,
                    IPV6_BOUND_IF,
                    &mutableIdx,
                    socklen_t(MemoryLayout<UInt32>.size)
                )
            } else {
                bindIfResult = setsockopt(
                    sock,
                    IPPROTO_IP,
                    IP_BOUND_IF,
                    &mutableIdx,
                    socklen_t(MemoryLayout<UInt32>.size)
                )
            }
            guard bindIfResult == 0 else {
                Darwin.close(sock)
                return nil
            }
            resolvedIfIndex = idx
        }

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
        self.boundInterfaceIndex = resolvedIfIndex

        let source = DispatchSource.makeReadSource(fileDescriptor: sock, queue: queue)
        source.setEventHandler { [weak self] in
            guard let self, !self.isClosed else { return }
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

    deinit {
        close()
    }

    private var isClosed: Bool {
        closeLock.lock()
        defer { closeLock.unlock() }
        return closed
    }

    @discardableResult
    func send(_ data: Data, to destination: sockaddr_storage) -> Bool {
        guard !isClosed,
              var dest = UDPEndpointResolver.adaptSockAddr(destination, forSocketFamily: family) else {
            return false
        }
        let addrLen = UDPEndpointResolver.sockAddrLength(dest)
        return data.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return false }
            let sent = withUnsafePointer(to: &dest) { destPtr in
                destPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { saPtr in
                    Darwin.sendto(fd, base, data.count, 0, saPtr, addrLen)
                }
            }
            return sent == data.count
        }
    }

    func close() {
        closeLock.lock()
        guard !closed else {
            closeLock.unlock()
            return
        }
        closed = true
        let source = readSource
        readSource = nil
        closeLock.unlock()
        source?.cancel()
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
    private var encoderLoadCeilingBps: Int?
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
        peerPort: UInt16?,
        boundInterfaceName: String? = nil
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
        let preferIPv6 = resolvedPeer.map { Int32($0.ss_family) == AF_INET6 }
            ?? UDPEndpointResolver.prefersIPv6(host: peerHost)

        let receiveCallback: (Data, sockaddr_storage) -> Void = { [weak self] data, addr in
            self?.handleIncomingDatagram(data, from: addr)
        }
        let openedSocket = NonBlockingUDPSocket(
            preferIPv6: preferIPv6,
            boundInterfaceName: boundInterfaceName,
            queue: queue,
            onReceive: receiveCallback
        ) ?? (peerHost == nil && preferIPv6 ? NonBlockingUDPSocket(
            preferIPv6: false,
            boundInterfaceName: boundInterfaceName,
            queue: queue,
            onReceive: receiveCallback
        ) : nil)
        guard let boundSocket = openedSocket else {
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

    deinit {
        pacerTimer?.cancel()
        socket?.close()
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

    /// Updates optional encoder hardware load ceiling without overwriting `bwe.currentBitrate`
    /// with post-FEC encoder bitrate. Pacer wire budget remains pre-FEC (`min(bwe, ceiling)`).
    func updateEncoderLoadCeiling(_ ceilingBps: Int?) {
        queue.async { [weak self] in
            guard let self, !self.isStoppedInternal else { return }
            let sanitized = ceilingBps.flatMap { $0 > 0 ? $0 : nil }
            self.encoderLoadCeilingBps = sanitized
            self.pacer.updateTargetBitrate(self.currentWireBudgetBpsOnQueue)
        }
    }

    /// Synchronizes both `bwe` and `pacer` to an explicit manual target wire bitrate.
    func syncManualTargetBitrate(_ bitrateBps: Int) {
        queue.async { [weak self] in
            guard let self, !self.isStoppedInternal else { return }
            self.bwe.syncTargetBitrate(bitrateBps)
            self.pacer.updateTargetBitrate(self.currentWireBudgetBpsOnQueue)
        }
    }

    func updateTargetBitrate(_ bitrateBps: Int) {
        syncManualTargetBitrate(bitrateBps)
    }

    func snapshotBitrateBudgets() -> (bweBitrateBps: Int, wireBudgetBps: Int, pacerRateBps: Int, effectiveEncoderBps: Int) {
        queue.sync {
            let wireBudget = currentWireBudgetBpsOnQueue
            let effectiveEncoder = bwe.effectiveEncoderBitrate(loadCeilingBps: encoderLoadCeilingBps)
            return (bwe.currentBitrate, wireBudget, pacer.pacingRateBps, effectiveEncoder)
        }
    }

    private var currentWireBudgetBpsOnQueue: Int {
        encoderLoadCeilingBps.map { min(bwe.currentBitrate, $0) } ?? bwe.currentBitrate
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
                    packetType: .videoData,
                    flags: flags,
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
                    packetType: .videoParity,
                    flags: flags,
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
        var pendingBytes = 0
        for item in burst {
            if socket.send(item.datagram, to: dest) {
                pendingBytes += item.datagram.count
                if item.completesVideoFrame {
                    onBytesSent?(pendingBytes, true)
                    pendingBytes = 0
                }
            }
        }
        if pendingBytes > 0 {
            onBytesSent?(pendingBytes, false)
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
                        packetType: .videoData,
                        flags: flags,
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
                let effectiveEncoderBps = bwe.effectiveEncoderBitrate(loadCeilingBps: encoderLoadCeilingBps)
                pacer.updateTargetBitrate(currentWireBudgetBpsOnQueue)
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
    static let maxInitialProbes = 6
    static let probeRetryIntervalNs: UInt64 = 150_000_000

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
    private var receivedAnySenderPacket = false
    private var initialProbesSent = 0
    private var lastProbeSentMonoNs: UInt64 = 0

    var onFrameReady: ((UInt64, UDPMediaFrameEnvelope) -> Void)?
    var onKeyframeNeeded: ((UInt64, String) -> Void)?

    init?(
        config: UDPMediaConfigMessage,
        generation: UInt64,
        senderHost: String?,
        boundInterfaceName: String? = nil
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
        let preferIPv6 = self.senderAddress.map { Int32($0.ss_family) == AF_INET6 }
            ?? UDPEndpointResolver.prefersIPv6(host: senderHost)

        let receiveCallback: (Data, sockaddr_storage) -> Void = { [weak self] data, addr in
            self?.handleIncomingDatagram(data, from: addr)
        }
        let openedSocket = NonBlockingUDPSocket(
            preferIPv6: preferIPv6,
            boundInterfaceName: boundInterfaceName,
            queue: queue,
            onReceive: receiveCallback
        ) ?? (senderHost == nil && preferIPv6 ? NonBlockingUDPSocket(
            preferIPv6: false,
            boundInterfaceName: boundInterfaceName,
            queue: queue,
            onReceive: receiveCallback
        ) : nil)
        guard let boundSocket = openedSocket else {
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
            guard let self, !self.stopped else { return }
            let nowNs = Self.nowMonoNs()
            if self.sendProbeOnQueue(isAck: false) {
                self.initialProbesSent = 1
                self.lastProbeSentMonoNs = nowNs
            }
        }
    }

    deinit {
        timer?.cancel()
        socket?.close()
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

    @discardableResult
    private func sendProbeOnQueue(isAck: Bool) -> Bool {
        guard let dest = senderAddress, let socket else { return false }
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
        ) else { return false }
        return socket.send(datagram, to: dest)
    }

    private func handleIncomingDatagram(_ datagram: Data, from sourceAddr: sockaddr_storage) {
        guard !stopped else { return }
        guard let packet = try? crypto.open(datagram: datagram, expectedDirection: .senderToReceiver) else {
            return
        }
        senderAddress = sourceAddr
        receivedAnySenderPacket = true
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
        if !receivedAnySenderPacket,
           initialProbesSent < Self.maxInitialProbes,
           (lastProbeSentMonoNs == 0
            || (monoNs >= lastProbeSentMonoNs && monoNs - lastProbeSentMonoNs >= Self.probeRetryIntervalNs)) {
            if sendProbeOnQueue(isAck: false) {
                initialProbesSent += 1
                lastProbeSentMonoNs = monoNs
            }
        }
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

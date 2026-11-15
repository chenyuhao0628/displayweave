import CryptoKit
import Foundation
#if canImport(AudioToolbox)
import AudioToolbox
import CoreAudioTypes
#endif

enum UDPMediaPacketType: UInt8, Sendable, Equatable {
    case videoData = 0
    case videoParity = 1
    case nack = 2
    case feedback = 3
    case probe = 4
    case cursor = 5
    case audio = 6
}

struct UDPMediaFlags: OptionSet, Sendable, Equatable {
    let rawValue: UInt8

    static let keyframe = UDPMediaFlags(rawValue: 1 << 0)
    static let endOfFrame = UDPMediaFlags(rawValue: 1 << 1)
    static let retransmit = UDPMediaFlags(rawValue: 1 << 2)
    static let probeAck = UDPMediaFlags(rawValue: 1 << 2)
}

enum UDPMediaDirection: UInt8, Sendable, Equatable {
    case senderToReceiver = 0
    case receiverToSender = 1

    var label: String {
        switch self {
        case .senderToReceiver: return "s2r"
        case .receiverToSender: return "r2s"
        }
    }
}

enum UDPMediaError: Error, Equatable {
    case packetTooShort
    case packetTooLarge
    case unsupportedVersion(UInt8)
    case invalidPacketType(UInt8)
    case invalidFragmentBounds
    case epochMismatch
    case replayRejected
    case authenticationFailed
    case invalidKeyMaterial
    case malformedControlPayload
}

/// Compact 16-byte wire header for `udpMediaV1` packets.
/// Every byte is authenticated as Additional Authenticated Data (AAD) in AES-128-GCM.
struct UDPMediaHeader: Equatable, Sendable {
    static let currentVersion: UInt8 = 1
    static let byteLength = 16
    static let gcmTagLength = 16
    static let maxPayloadLength = 1200
    static let maxDatagramLength = byteLength + maxPayloadLength + gcmTagLength
    static let maxFragmentsPerFrame: UInt16 = 2048

    var version: UInt8 = Self.currentVersion
    var packetType: UDPMediaPacketType
    var flags: UDPMediaFlags
    var epochTag: UInt8
    var packetSeq: UInt16
    var sendTimeUs: UInt32
    var frameId: UInt32
    var fragIndex: UInt16
    var fragCount: UInt16

    static func makeEpochTag(sessionEpoch: Int64) -> UInt8 {
        UInt8(truncatingIfNeeded: UInt64(bitPattern: sessionEpoch))
    }

    @inline(__always)
    static func frameIdDelta(_ lhs: UInt32, _ rhs: UInt32) -> Int32 {
        Int32(bitPattern: lhs &- rhs)
    }

    @inline(__always)
    static func isFrameIdNewer(_ candidate: UInt32, than baseline: UInt32) -> Bool {
        Int32(bitPattern: candidate &- baseline) > 0
    }

    func encode() -> Data {
        var data = Data(capacity: Self.byteLength)
        let byte0 = ((version & 0x03) << 6)
            | ((packetType.rawValue & 0x07) << 3)
            | (flags.rawValue & 0x07)
        data.append(byte0)
        data.append(epochTag)
        Self.appendUInt16(&data, packetSeq)
        Self.appendUInt32(&data, sendTimeUs)
        Self.appendUInt32(&data, frameId)
        Self.appendUInt16(&data, fragIndex)
        Self.appendUInt16(&data, fragCount)
        return data
    }

    static func decode(from data: Data) throws -> UDPMediaHeader {
        guard data.count >= byteLength else {
            throw UDPMediaError.packetTooShort
        }
        let base = data.startIndex
        let byte0 = data[base]
        let version = (byte0 >> 6) & 0x03
        guard version == currentVersion else {
            throw UDPMediaError.unsupportedVersion(version)
        }
        let rawType = (byte0 >> 3) & 0x07
        guard let packetType = UDPMediaPacketType(rawValue: rawType) else {
            throw UDPMediaError.invalidPacketType(rawType)
        }
        let flags = UDPMediaFlags(rawValue: byte0 & 0x07)
        let epochTag = data[base + 1]
        let packetSeq = readUInt16(data, offset: 2)
        let sendTimeUs = readUInt32(data, offset: 4)
        let frameId = readUInt32(data, offset: 8)
        let fragIndex = readUInt16(data, offset: 12)
        let fragCount = readUInt16(data, offset: 14)

        if packetType == .videoData {
            guard fragCount >= 1,
                  fragCount <= maxFragmentsPerFrame,
                  fragIndex < fragCount else {
                throw UDPMediaError.invalidFragmentBounds
            }
        } else if packetType == .cursor || packetType == .audio {
            guard fragIndex == 0, fragCount == 1 else {
                throw UDPMediaError.invalidFragmentBounds
            }
        }
        return UDPMediaHeader(
            version: version,
            packetType: packetType,
            flags: flags,
            epochTag: epochTag,
            packetSeq: packetSeq,
            sendTimeUs: sendTimeUs,
            frameId: frameId,
            fragIndex: fragIndex,
            fragCount: fragCount
        )
    }

    static func appendUInt16(_ data: inout Data, _ value: UInt16) {
        data.append(UInt8((value >> 8) & 0xFF))
        data.append(UInt8(value & 0xFF))
    }

    static func appendUInt32(_ data: inout Data, _ value: UInt32) {
        data.append(UInt8((value >> 24) & 0xFF))
        data.append(UInt8((value >> 16) & 0xFF))
        data.append(UInt8((value >> 8) & 0xFF))
        data.append(UInt8(value & 0xFF))
    }

    static func appendUInt64(_ data: inout Data, _ value: UInt64) {
        for shift in stride(from: 56, through: 0, by: -8) {
            data.append(UInt8((value >> shift) & 0xFF))
        }
    }

    static func readUInt16(_ data: Data, offset: Int) -> UInt16 {
        let idx = data.startIndex + offset
        return (UInt16(data[idx]) << 8) | UInt16(data[idx + 1])
    }

    static func readUInt32(_ data: Data, offset: Int) -> UInt32 {
        let idx = data.startIndex + offset
        return (UInt32(data[idx]) << 24)
            | (UInt32(data[idx + 1]) << 16)
            | (UInt32(data[idx + 2]) << 8)
            | UInt32(data[idx + 3])
    }

    static func readUInt64(_ data: Data, offset: Int) -> UInt64 {
        let idx = data.startIndex + offset
        var result: UInt64 = 0
        for i in 0..<8 {
            result = (result << 8) | UInt64(data[idx + i])
        }
        return result
    }
}

/// 1024-packet sliding anti-replay window with 64-bit rollover counter (ROC)
/// estimation. Only mutates state after AEAD tag verification succeeds.
struct UDPAntiReplayWindow: Sendable, Equatable {
    static let windowSize: UInt64 = 1024
    private static let wordCount = 16 // 16 * 64 = 1024 bits

    private(set) var highestAuthenticatedSeq: UInt64 = 0
    private(set) var hasAuthenticatedAny = false
    private var words = [UInt64](repeating: 0, count: wordCount)

    /// Reconstructs the closest 64-bit extended sequence number from a 16-bit
    /// wire `packetSeq` without mutating receiver state.
    func estimateExtendedSequence(packetSeq: UInt16) -> UInt64 {
        let seq16 = UInt64(packetSeq)
        guard hasAuthenticatedAny else {
            return seq16
        }
        let highestLow16 = highestAuthenticatedSeq & 0xFFFF
        let baseEpoch = highestAuthenticatedSeq & ~UInt64(0xFFFF)
        let delta = Int64(seq16) - Int64(highestLow16)
        if delta >= -32768 && delta <= 32767 {
            return UInt64(Int64(highestAuthenticatedSeq) + delta)
        } else if delta < -32768 {
            return baseEpoch + 0x10000 + seq16
        } else {
            return baseEpoch >= 0x10000 ? (baseEpoch - 0x10000 + seq16) : seq16
        }
    }

    /// Pre-decryption check: returns `false` if `extendedSeq` is outside the
    /// 1024-packet window or has already been authenticated.
    func canAccept(_ extendedSeq: UInt64) -> Bool {
        guard hasAuthenticatedAny else { return true }
        if extendedSeq > highestAuthenticatedSeq {
            return true
        }
        let age = highestAuthenticatedSeq - extendedSeq
        guard age < Self.windowSize else {
            return false
        }
        let wordIndex = Int(age >> 6)
        let bitMask = UInt64(1) << (age & 63)
        return (words[wordIndex] & bitMask) == 0
    }

    /// Post-decryption commit: marks `extendedSeq` as authenticated and slides
    /// the 1024-packet window forward when `extendedSeq > highestAuthenticatedSeq`.
    mutating func recordAuthenticated(_ extendedSeq: UInt64) {
        if !hasAuthenticatedAny {
            hasAuthenticatedAny = true
            highestAuthenticatedSeq = extendedSeq
            words[0] = 1
            return
        }
        if extendedSeq > highestAuthenticatedSeq {
            let shift = extendedSeq - highestAuthenticatedSeq
            shiftWindow(by: shift)
            highestAuthenticatedSeq = extendedSeq
            words[0] |= 1
            return
        }
        let age = highestAuthenticatedSeq - extendedSeq
        guard age < Self.windowSize else { return }
        let wordIndex = Int(age >> 6)
        let bitMask = UInt64(1) << (age & 63)
        words[wordIndex] |= bitMask
    }

    private mutating func shiftWindow(by shift: UInt64) {
        guard shift > 0 else { return }
        if shift >= Self.windowSize {
            for i in 0..<Self.wordCount { words[i] = 0 }
            return
        }
        let wordShift = Int(shift >> 6)
        let bitShift = Int(shift & 63)
        if wordShift > 0 {
            for i in stride(from: Self.wordCount - 1, through: wordShift, by: -1) {
                words[i] = words[i - wordShift]
            }
            for i in 0..<wordShift {
                words[i] = 0
            }
        }
        if bitShift > 0 {
            for i in stride(from: Self.wordCount - 1, through: 1, by: -1) {
                words[i] = (words[i] << bitShift) | (words[i - 1] >> (64 - bitShift))
            }
            words[0] <<= bitShift
        }
    }
}

/// Deterministic RFC 5869 HKDF-SHA256 key derivation and per-packet AES-128-GCM
/// sealer/opener with 64-bit extended sequence nonces.
struct UDPMediaKeyMaterial: Sendable, Equatable {
    static let rootSecretByteLength = 32
    static let hkdfSalt = Data("DisplayWeave-UDPMediaV1-Salt-2026".utf8)

    let sessionEpoch: Int64
    let senderToReceiverKey: Data
    let senderToReceiverSalt: Data
    let receiverToSenderKey: Data
    let receiverToSenderSalt: Data

    static func generateRootSecret() -> Data {
        var generator = SystemRandomNumberGenerator()
        var bytes = [UInt8](repeating: 0, count: rootSecretByteLength)
        for index in bytes.indices {
            bytes[index] = UInt8.random(in: 0...255, using: &generator)
        }
        return Data(bytes)
    }

    static func derive(rootSecret: Data, sessionEpoch: Int64) throws -> UDPMediaKeyMaterial {
        guard rootSecret.count == rootSecretByteLength, sessionEpoch > 0 else {
            throw UDPMediaError.invalidKeyMaterial
        }
        let prk = hmacSHA256(key: hkdfSalt, data: rootSecret)
        let s2rInfo = Data("displayweave-udp-v1|s2r|\(sessionEpoch)".utf8)
        let r2sInfo = Data("displayweave-udp-v1|r2s|\(sessionEpoch)".utf8)
        let s2rOKM = hkdfExpand(prk: prk, info: s2rInfo, length: 28)
        let r2sOKM = hkdfExpand(prk: prk, info: r2sInfo, length: 28)
        return UDPMediaKeyMaterial(
            sessionEpoch: sessionEpoch,
            senderToReceiverKey: s2rOKM.subdata(in: 0..<16),
            senderToReceiverSalt: s2rOKM.subdata(in: 16..<28),
            receiverToSenderKey: r2sOKM.subdata(in: 0..<16),
            receiverToSenderSalt: r2sOKM.subdata(in: 16..<28)
        )
    }

    func nonce(for direction: UDPMediaDirection, extendedSequence: UInt64) -> Data {
        let baseSalt = direction == .senderToReceiver ? senderToReceiverSalt : receiverToSenderSalt
        var bytes = [UInt8](baseSalt)
        let directionalSeq = (UInt64(direction.rawValue & 0x01) << 63)
            | (extendedSequence & 0x7FFF_FFFF_FFFF_FFFF)
        for i in 0..<8 {
            let shift = (7 - i) * 8
            bytes[4 + i] ^= UInt8((directionalSeq >> shift) & 0xFF)
        }
        return Data(bytes)
    }

    private static func hmacSHA256(key: Data, data: Data) -> Data {
        let mac = HMAC<SHA256>.authenticationCode(for: data, using: SymmetricKey(data: key))
        return Data(mac)
    }

    private static func hkdfExpand(prk: Data, info: Data, length: Int) -> Data {
        var result = Data()
        var previous = Data()
        var counter: UInt8 = 1
        while result.count < length {
            var input = Data()
            input.append(previous)
            input.append(info)
            input.append(counter)
            previous = hmacSHA256(key: prk, data: input)
            result.append(previous)
            counter &+= 1
        }
        return result.prefix(length)
    }
}

struct AuthenticatedUDPPacket: Sendable, Equatable {
    let header: UDPMediaHeader
    let extendedSequence: UInt64
    let payload: Data
}

/// Stateful per-session cryptographic context managing 64-bit outgoing sequence
/// numbers, incoming 1024-packet anti-replay verification, and AES-128-GCM.
struct UDPMediaCryptoSession: Sendable {
    let keyMaterial: UDPMediaKeyMaterial
    let epochTag: UInt8
    private let s2rSymmetricKey: SymmetricKey
    private let r2sSymmetricKey: SymmetricKey
    private(set) var nextOutgoingSequence: UInt64 = 1
    private(set) var replayWindow = UDPAntiReplayWindow()

    init(keyMaterial: UDPMediaKeyMaterial) {
        self.keyMaterial = keyMaterial
        self.epochTag = UDPMediaHeader.makeEpochTag(sessionEpoch: keyMaterial.sessionEpoch)
        self.s2rSymmetricKey = SymmetricKey(data: keyMaterial.senderToReceiverKey)
        self.r2sSymmetricKey = SymmetricKey(data: keyMaterial.receiverToSenderKey)
    }

    mutating func seal(
        direction: UDPMediaDirection,
        packetType: UDPMediaPacketType,
        flags: UDPMediaFlags,
        sendTimeUs: UInt32,
        frameId: UInt32,
        fragIndex: UInt16,
        fragCount: UInt16,
        payload: Data
    ) throws -> (datagram: Data, header: UDPMediaHeader, extendedSequence: UInt64) {
        guard payload.count <= UDPMediaHeader.maxPayloadLength else {
            throw UDPMediaError.packetTooLarge
        }
        let extendedSeq = nextOutgoingSequence
        nextOutgoingSequence &+= 1
        let header = UDPMediaHeader(
            packetType: packetType,
            flags: flags,
            epochTag: epochTag,
            packetSeq: UInt16(truncatingIfNeeded: extendedSeq),
            sendTimeUs: sendTimeUs,
            frameId: frameId,
            fragIndex: fragIndex,
            fragCount: fragCount
        )
        let headerBytes = header.encode()
        let nonceData = keyMaterial.nonce(for: direction, extendedSequence: extendedSeq)
        let nonce = try AES.GCM.Nonce(data: nonceData)
        let key = direction == .senderToReceiver ? s2rSymmetricKey : r2sSymmetricKey
        let sealed = try AES.GCM.seal(
            payload,
            using: key,
            nonce: nonce,
            authenticating: headerBytes
        )
        var datagram = Data(capacity: headerBytes.count + payload.count + UDPMediaHeader.gcmTagLength)
        datagram.append(headerBytes)
        datagram.append(sealed.ciphertext)
        datagram.append(sealed.tag)
        return (datagram, header, extendedSeq)
    }

    mutating func open(
        datagram: Data,
        expectedDirection: UDPMediaDirection
    ) throws -> AuthenticatedUDPPacket {
        let minLength = UDPMediaHeader.byteLength + UDPMediaHeader.gcmTagLength
        guard datagram.count >= minLength else {
            throw UDPMediaError.packetTooShort
        }
        guard datagram.count <= UDPMediaHeader.maxDatagramLength else {
            throw UDPMediaError.packetTooLarge
        }
        let header = try UDPMediaHeader.decode(from: datagram)
        guard header.epochTag == epochTag else {
            throw UDPMediaError.epochMismatch
        }
        let candidateSeq = replayWindow.estimateExtendedSequence(packetSeq: header.packetSeq)
        guard replayWindow.canAccept(candidateSeq) else {
            throw UDPMediaError.replayRejected
        }
        let headerBytes = datagram.subdata(in: datagram.startIndex..<(datagram.startIndex + UDPMediaHeader.byteLength))
        let ciphertextEnd = datagram.endIndex - UDPMediaHeader.gcmTagLength
        let ciphertext = datagram.subdata(in: (datagram.startIndex + UDPMediaHeader.byteLength)..<ciphertextEnd)
        let tag = datagram.subdata(in: ciphertextEnd..<datagram.endIndex)
        let nonceData = keyMaterial.nonce(for: expectedDirection, extendedSequence: candidateSeq)
        let key = expectedDirection == .senderToReceiver ? s2rSymmetricKey : r2sSymmetricKey
        let plaintext: Data
        do {
            let nonce = try AES.GCM.Nonce(data: nonceData)
            let box = try AES.GCM.SealedBox(nonce: nonce, ciphertext: ciphertext, tag: tag)
            plaintext = try AES.GCM.open(box, using: key, authenticating: headerBytes)
        } catch {
            throw UDPMediaError.authenticationFailed
        }
        replayWindow.recordAuthenticated(candidateSeq)
        return AuthenticatedUDPPacket(
            header: header,
            extendedSequence: candidateSeq,
            payload: plaintext
        )
    }
}

/// Compact 20-byte NACK payload reporting missing fragments for a frame.
struct UDPMediaNackPayload: Equatable, Sendable {
    static let byteLength = 20

    var frameId: UInt32
    var baseFragIndex: UInt16
    var missingCount: UInt16
    var missingBitmap: UInt64
    var rttEstimateUs: UInt32

    func encode() -> Data {
        var data = Data(capacity: Self.byteLength)
        UDPMediaHeader.appendUInt32(&data, frameId)
        UDPMediaHeader.appendUInt16(&data, baseFragIndex)
        UDPMediaHeader.appendUInt16(&data, missingCount)
        UDPMediaHeader.appendUInt64(&data, missingBitmap)
        UDPMediaHeader.appendUInt32(&data, rttEstimateUs)
        return data
    }

    static func decode(from data: Data) throws -> UDPMediaNackPayload {
        guard data.count >= byteLength else {
            throw UDPMediaError.malformedControlPayload
        }
        return UDPMediaNackPayload(
            frameId: UDPMediaHeader.readUInt32(data, offset: 0),
            baseFragIndex: UDPMediaHeader.readUInt16(data, offset: 4),
            missingCount: UDPMediaHeader.readUInt16(data, offset: 6),
            missingBitmap: UDPMediaHeader.readUInt64(data, offset: 8),
            rttEstimateUs: UDPMediaHeader.readUInt32(data, offset: 16)
        )
    }

    func missingFragmentIndices(maxFragCount: UInt16) -> [UInt16] {
        var result: [UInt16] = []
        for bit in 0..<64 {
            guard (missingBitmap & (UInt64(1) << bit)) != 0 else { continue }
            let idx = Int(baseFragIndex) + bit
            guard idx < Int(maxFragCount), idx < Int(UDPMediaHeader.maxFragmentsPerFrame) else { continue }
            result.append(UInt16(idx))
        }
        return result
    }
}

/// Compact 28-byte receiver feedback payload for UDP RTT, loss, and delay-gradient BWE.
struct UDPMediaFeedbackPayload: Equatable, Sendable {
    static let byteLength = 28

    var highestSeq: UInt64
    var receivedCount: UInt32
    var lostCount: UInt32
    var arrivalGradientUs: Int32
    var decodeQueueMs: UInt16
    var renderFps: UInt16
    var echoSendTimeUs: UInt32

    func encode() -> Data {
        var data = Data(capacity: Self.byteLength)
        UDPMediaHeader.appendUInt64(&data, highestSeq)
        UDPMediaHeader.appendUInt32(&data, receivedCount)
        UDPMediaHeader.appendUInt32(&data, lostCount)
        UDPMediaHeader.appendUInt32(&data, UInt32(bitPattern: arrivalGradientUs))
        UDPMediaHeader.appendUInt16(&data, decodeQueueMs)
        UDPMediaHeader.appendUInt16(&data, renderFps)
        UDPMediaHeader.appendUInt32(&data, echoSendTimeUs)
        return data
    }

    static func decode(from data: Data) throws -> UDPMediaFeedbackPayload {
        guard data.count >= byteLength else {
            throw UDPMediaError.malformedControlPayload
        }
        return UDPMediaFeedbackPayload(
            highestSeq: UDPMediaHeader.readUInt64(data, offset: 0),
            receivedCount: UDPMediaHeader.readUInt32(data, offset: 8),
            lostCount: UDPMediaHeader.readUInt32(data, offset: 12),
            arrivalGradientUs: Int32(bitPattern: UDPMediaHeader.readUInt32(data, offset: 16)),
            decodeQueueMs: UDPMediaHeader.readUInt16(data, offset: 20),
            renderFps: UDPMediaHeader.readUInt16(data, offset: 22),
            echoSendTimeUs: UDPMediaHeader.readUInt32(data, offset: 24)
        )
    }
}

/// Compact 17-byte sender-to-receiver cursor state payload (`packetType = .cursor`).
/// Wire layout (big-endian):
/// `[0..7]` `sequence: UInt64`, `[8..11]` `normalizedX: Float32` IEEE-754 (`0...1` finite),
/// `[12..15]` `normalizedY: Float32` IEEE-754 (`0...1` finite), `[16]` `visible: UInt8` (`1` or `0`).
struct UDPMediaCursorPayload: Equatable, Sendable {
    static let byteLength = 17

    var sequence: UInt64
    var normalizedX: Float32
    var normalizedY: Float32
    var visible: Bool

    var visibleByte: UInt8 { visible ? 1 : 0 }

    var isValid: Bool {
        normalizedX.isFinite
            && normalizedY.isFinite
            && normalizedX >= 0
            && normalizedX <= 1
            && normalizedY >= 0
            && normalizedY <= 1
    }

    init(sequence: UInt64, normalizedX: Float32, normalizedY: Float32, visible: Bool) {
        self.sequence = sequence
        self.normalizedX = normalizedX == 0 ? 0 : normalizedX
        self.normalizedY = normalizedY == 0 ? 0 : normalizedY
        self.visible = visible
    }

    init(sequence: UInt64, normalizedX: Double, normalizedY: Double, visible: Bool) {
        let fx = Float32(normalizedX)
        let fy = Float32(normalizedY)
        self.init(sequence: sequence, normalizedX: fx, normalizedY: fy, visible: visible)
    }

    func encode() -> Data {
        let clampedX: Float32 = normalizedX.isFinite ? min(max(normalizedX, 0), 1) : 0
        let clampedY: Float32 = normalizedY.isFinite ? min(max(normalizedY, 0), 1) : 0
        let canonicalX: Float32 = clampedX == 0 ? 0 : clampedX
        let canonicalY: Float32 = clampedY == 0 ? 0 : clampedY
        var data = Data(capacity: Self.byteLength)
        UDPMediaHeader.appendUInt64(&data, sequence)
        UDPMediaHeader.appendUInt32(&data, canonicalX.bitPattern)
        UDPMediaHeader.appendUInt32(&data, canonicalY.bitPattern)
        data.append(visible ? 1 : 0)
        return data
    }

    static func decode(from data: Data) throws -> UDPMediaCursorPayload {
        guard data.count == byteLength else {
            throw UDPMediaError.malformedControlPayload
        }
        let seq = UDPMediaHeader.readUInt64(data, offset: 0)
        let rawX = Float32(bitPattern: UDPMediaHeader.readUInt32(data, offset: 8))
        let rawY = Float32(bitPattern: UDPMediaHeader.readUInt32(data, offset: 12))
        let visByte = data[data.startIndex + 16]
        guard rawX.isFinite,
              rawY.isFinite,
              rawX >= 0,
              rawX <= 1,
              rawY >= 0,
              rawY <= 1,
              (visByte == 0 || visByte == 1) else {
            throw UDPMediaError.malformedControlPayload
        }
        return UDPMediaCursorPayload(
            sequence: seq,
            normalizedX: rawX == 0 ? 0 : rawX,
            normalizedY: rawY == 0 ? 0 : rawY,
            visible: visByte == 1
        )
    }
}

/// Compact sender-to-receiver audio packet payload (`packetType = .audio` or TCP `"audioFrame"`).
/// Wire layout (big-endian header + encoded audio body `<= 1152` bytes):
/// `[0..3]` `audioSeq: UInt32`, `[4..11]` `captureTimestampMs: Int64`,
/// `[12..13]` `sampleRate: UInt16`, `[14]` `channels: UInt8` (`1` or `2`),
/// `[15]` `formatFlags: UInt8` (`0` = S16LE PCM, `1` = Opus), `[16...]` audio payload bytes.
struct UDPMediaAudioPayload: Equatable, Sendable {
    static let headerByteLength = 16
    static let maxPCMBytes = 1152
    static let maxOpusBytes = 1152
    static let formatPCM16LE: UInt8 = 0
    static let formatOpus: UInt8 = 1

    var audioSeq: UInt32
    var captureTimestampMs: Int64
    var sampleRate: UInt16
    var channels: UInt8
    var formatFlags: UInt8
    var pcmBytes: Data

    init(
        audioSeq: UInt32,
        captureTimestampMs: Int64,
        sampleRate: UInt16 = 48_000,
        channels: UInt8 = 2,
        formatFlags: UInt8 = Self.formatPCM16LE,
        pcmBytes: Data
    ) {
        self.audioSeq = audioSeq
        self.captureTimestampMs = captureTimestampMs
        self.sampleRate = sampleRate
        self.channels = channels
        self.formatFlags = formatFlags
        self.pcmBytes = pcmBytes
    }

    var isValid: Bool {
        guard sampleRate > 0,
              (channels == 1 || channels == 2),
              !pcmBytes.isEmpty,
              pcmBytes.count <= Self.maxPCMBytes else {
            return false
        }
        switch formatFlags {
        case Self.formatPCM16LE:
            return pcmBytes.count % (Int(channels) * 2) == 0
        case Self.formatOpus:
            return sampleRate == 48_000
        default:
            return false
        }
    }

    func encode() -> Data {
        var data = Data(capacity: Self.headerByteLength + pcmBytes.count)
        UDPMediaHeader.appendUInt32(&data, audioSeq)
        UDPMediaHeader.appendUInt64(&data, UInt64(bitPattern: captureTimestampMs))
        UDPMediaHeader.appendUInt16(&data, sampleRate)
        data.append(channels)
        data.append(formatFlags)
        data.append(pcmBytes)
        return data
    }

    static func decode(from data: Data) throws -> UDPMediaAudioPayload {
        guard data.count > headerByteLength else {
            throw UDPMediaError.malformedControlPayload
        }
        let pcmCount = data.count - headerByteLength
        guard pcmCount <= maxPCMBytes else {
            throw UDPMediaError.malformedControlPayload
        }
        let seq = UDPMediaHeader.readUInt32(data, offset: 0)
        let captureMs = Int64(bitPattern: UDPMediaHeader.readUInt64(data, offset: 4))
        let rate = UDPMediaHeader.readUInt16(data, offset: 12)
        let ch = data[data.startIndex + 14]
        let fmt = data[data.startIndex + 15]
        let validBody: Bool
        switch fmt {
        case formatPCM16LE:
            validBody = rate > 0 && (ch == 1 || ch == 2) && pcmCount % (Int(ch) * 2) == 0
        case formatOpus:
            validBody = rate == 48_000 && (ch == 1 || ch == 2) && pcmCount >= 1
        default:
            validBody = false
        }
        guard validBody else {
            throw UDPMediaError.malformedControlPayload
        }
        let pcm = data.subdata(in: (data.startIndex + headerByteLength)..<data.endIndex)
        return UDPMediaAudioPayload(
            audioSeq: seq,
            captureTimestampMs: captureMs,
            sampleRate: rate,
            channels: ch,
            formatFlags: fmt,
            pcmBytes: pcm
        )
    }
}

/// Bounded JSON control envelope delivering `UDPMediaAudioPayload` over authenticated TCP (`tcpAudioV1`).
enum TCPAudioFrameMessage {
    static let messageType = "audioFrame"
    static let maxControlBytes = 4_096
    static let maxEncodedPayloadChars = 2_048

    static func encodeJSONString(_ payload: UDPMediaAudioPayload) -> String? {
        guard payload.isValid else { return nil }
        let raw = payload.encode()
        guard raw.count <= UDPMediaAudioPayload.headerByteLength + UDPMediaAudioPayload.maxPCMBytes else {
            return nil
        }
        let b64 = raw.base64EncodedString()
        let json = "{\"type\":\"\(messageType)\",\"payload\":\"\(b64)\"}"
        guard json.utf8.count <= maxControlBytes else { return nil }
        return json
    }

    static func encodeJSONData(_ payload: UDPMediaAudioPayload) -> Data? {
        guard let json = encodeJSONString(payload) else { return nil }
        return Data(json.utf8)
    }

    static func decode(jsonData: Data) throws -> UDPMediaAudioPayload {
        guard !jsonData.isEmpty, jsonData.count <= maxControlBytes else {
            throw UDPMediaError.malformedControlPayload
        }
        guard let object = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
            throw UDPMediaError.malformedControlPayload
        }
        return try decode(jsonObject: object, rawByteCount: jsonData.count)
    }

    static func decode(jsonObject: [String: Any], rawByteCount: Int = 0) throws -> UDPMediaAudioPayload {
        guard rawByteCount <= maxControlBytes,
              (jsonObject["type"] as? String) == messageType else {
            throw UDPMediaError.malformedControlPayload
        }
        let b64String = (jsonObject["payload"] as? String) ?? (jsonObject["d"] as? String)
        guard let b64 = b64String,
              !b64.isEmpty,
              b64.utf8.count <= maxEncodedPayloadChars,
              let raw = Data(base64Encoded: b64) else {
            throw UDPMediaError.malformedControlPayload
        }
        return try UDPMediaAudioPayload.decode(from: raw)
    }
}

/// Strict TCP audio backpressure policy ensuring outgoing audio never stalls video or input.
enum TCPAudioBackpressurePolicy {
    static let maxPendingVideoSends = 2
    static let maxPendingAudioSends = 2

    static func shouldSend(
        connectionReady: Bool,
        pendingVideoSends: Int,
        pendingAudioSends: Int,
        jsonByteCount: Int
    ) -> Bool {
        connectionReady
            && pendingVideoSends <= maxPendingVideoSends
            && pendingAudioSends < maxPendingAudioSends
            && jsonByteCount > 0
            && jsonByteCount <= TCPAudioFrameMessage.maxControlBytes
    }
}

/// Dynamic A/V lip-sync target watermark policy shared by Mac and iOS audio players.
/// Aligns audio playout buffering (`15ms...90ms` within a `120ms` hard ring cap) to active
/// video jitter/decode delay and trims drift whenever buffered audio exceeds `target + 25ms`.
struct AudioLipSyncPolicy: Sendable, Equatable {
    static let maxCapacityMs: Double = 120.0
    static let minTargetMs: Double = 15.0
    static let maxTargetMs: Double = 90.0
    static let defaultWiredTargetMs: Double = 20.0
    static let defaultUDPJitterTargetMs: Double = 45.0
    static let driftTrimMarginMs: Double = 25.0
    static let maxVideoSampleAgeMs: Double = 2_000.0
    static let maxClockDeltaSanityMs: Double = 500.0
    static let defaultMaxCapacityFrames: Int = 5_760
    static let defaultMinTargetFrames: Int = 720
    static let defaultMaxTargetFrames: Int = 4_320

    private(set) var sampleRate: Int
    private(set) var udpJitterActive: Bool
    private(set) var targetDelayMs: Double
    private var lastVideoCaptureToRenderDeltaMs: Double?
    private var lastVideoRenderMonoMs: Double?
    private var explicitPipelineDelayMs: Double?

    init(sampleRate: Int = 48_000, udpJitterActive: Bool = false) {
        self.sampleRate = max(8_000, sampleRate)
        self.udpJitterActive = udpJitterActive
        self.targetDelayMs = udpJitterActive ? Self.defaultUDPJitterTargetMs : Self.defaultWiredTargetMs
    }

    static func frames(forMilliseconds ms: Double, sampleRate: Int = 48_000) -> Int {
        max(1, Int((Double(max(8_000, sampleRate)) * ms / 1_000.0).rounded()))
    }

    var maxCapacityFrames: Int {
        Self.frames(forMilliseconds: Self.maxCapacityMs, sampleRate: sampleRate)
    }

    var minTargetFrames: Int {
        Self.frames(forMilliseconds: Self.minTargetMs, sampleRate: sampleRate)
    }

    var maxTargetFrames: Int {
        Self.frames(forMilliseconds: Self.maxTargetMs, sampleRate: sampleRate)
    }

    var targetBufferedFrames: Int {
        let raw = Self.frames(forMilliseconds: targetDelayMs, sampleRate: sampleRate)
        return min(max(raw, minTargetFrames), maxTargetFrames)
    }

    var driftTrimMarginFrames: Int {
        Self.frames(forMilliseconds: Self.driftTrimMarginMs, sampleRate: sampleRate)
    }

    var driftTrimThresholdFrames: Int {
        min(maxCapacityFrames, targetBufferedFrames + driftTrimMarginFrames)
    }

    mutating func setSampleRate(_ rate: Int) {
        sampleRate = max(8_000, rate)
    }

    mutating func reset(udpJitterActive: Bool = false) {
        self.udpJitterActive = udpJitterActive
        self.targetDelayMs = udpJitterActive ? Self.defaultUDPJitterTargetMs : Self.defaultWiredTargetMs
        self.lastVideoCaptureToRenderDeltaMs = nil
        self.lastVideoRenderMonoMs = nil
        self.explicitPipelineDelayMs = nil
    }

    mutating func updateTransportMode(udpJitterActive: Bool, explicitVideoDelayMs: Double? = nil) {
        let modeChanged = (self.udpJitterActive != udpJitterActive)
        self.udpJitterActive = udpJitterActive
        if let explicitVideoDelayMs, explicitVideoDelayMs.isFinite, explicitVideoDelayMs >= 0 {
            let clamped = min(max(explicitVideoDelayMs, Self.minTargetMs), Self.maxTargetMs)
            self.explicitPipelineDelayMs = clamped
            if modeChanged {
                targetDelayMs = clamped
            } else {
                targetDelayMs = min(max(0.80 * targetDelayMs + 0.20 * clamped, Self.minTargetMs), Self.maxTargetMs)
            }
        } else {
            self.explicitPipelineDelayMs = nil
            if modeChanged {
                targetDelayMs = udpJitterActive ? Self.defaultUDPJitterTargetMs : Self.defaultWiredTargetMs
            }
        }
    }

    mutating func recordVideoRender(captureTimestampMs: Int64, renderMonoMs: Double) {
        guard captureTimestampMs > 0, renderMonoMs.isFinite else { return }
        lastVideoCaptureToRenderDeltaMs = renderMonoMs - Double(captureTimestampMs)
        lastVideoRenderMonoMs = renderMonoMs
    }

    @discardableResult
    mutating func observeAudioArrival(captureTimestampMs: Int64, arrivalMonoMs: Double) -> Int {
        let baseline = explicitPipelineDelayMs
            ?? (udpJitterActive ? Self.defaultUDPJitterTargetMs : Self.defaultWiredTargetMs)
        if captureTimestampMs > 0,
           arrivalMonoMs.isFinite,
           let videoDelta = lastVideoCaptureToRenderDeltaMs,
           let videoMono = lastVideoRenderMonoMs {
            let videoAgeMs = arrivalMonoMs - videoMono
            if videoAgeMs >= -250.0 && videoAgeMs <= Self.maxVideoSampleAgeMs {
                let audioDelta = arrivalMonoMs - Double(captureTimestampMs)
                let relativeLeadMs = videoDelta - audioDelta
                if relativeLeadMs.isFinite && abs(relativeLeadMs) <= Self.maxClockDeltaSanityMs {
                    let clampedSample = min(max(relativeLeadMs, Self.minTargetMs), Self.maxTargetMs)
                    targetDelayMs = min(max(0.80 * targetDelayMs + 0.20 * clampedSample, Self.minTargetMs), Self.maxTargetMs)
                    return targetBufferedFrames
                }
            }
        }
        let clampedBase = min(max(baseline, Self.minTargetMs), Self.maxTargetMs)
        targetDelayMs = min(max(0.90 * targetDelayMs + 0.10 * clampedBase, Self.minTargetMs), Self.maxTargetMs)
        return targetBufferedFrames
    }

    func excessFramesToTrim(currentBufferedFrames: Int) -> Int {
        guard currentBufferedFrames > driftTrimThresholdFrames else { return 0 }
        return max(0, currentBufferedFrames - targetBufferedFrames)
    }
}

#if canImport(AudioToolbox)
/// Native `AudioToolbox` Opus -> S16LE PCM packet decoder shared by Mac and iOS receivers.
final class AppleOpusAudioDecoder {
    private static let endOfSinglePacketStatus: OSStatus = -77_401
    private static let maxDecodedFramesPerPacket: UInt32 = 2_880

    private var converter: AudioConverterRef?
    private var configuredChannels: UInt32 = 0
    private var configuredSampleRate: Double = 0
    private var decodeScratch = [UInt8]()

    private final class InputContext {
        var packetBytes: UnsafeRawPointer?
        var packetLength: Int = 0
        var packetDesc = AudioStreamPacketDescription()
        var consumed: Bool = false
    }

    private let inputContext = InputContext()

    deinit {
        reset()
    }

    func reset() {
        if let converter {
            AudioConverterDispose(converter)
            self.converter = nil
        }
        configuredChannels = 0
        configuredSampleRate = 0
    }

    func decodeToInterleavedS16LE(
        opusPacket: Data,
        sampleRate: Int = 48_000,
        channels: Int = 2
    ) -> Data? {
        guard sampleRate == 48_000,
              (1...2).contains(channels),
              !opusPacket.isEmpty,
              opusPacket.count <= UDPMediaAudioPayload.maxPCMBytes else {
            return nil
        }
        let ch = UInt32(channels)
        let rate = Double(sampleRate)
        if converter == nil || configuredChannels != ch || configuredSampleRate != rate {
            reset()
            var srcFormat = AudioStreamBasicDescription(
                mSampleRate: rate,
                mFormatID: kAudioFormatOpus,
                mFormatFlags: 0,
                mBytesPerPacket: 0,
                mFramesPerPacket: 960,
                mBytesPerFrame: 0,
                mChannelsPerFrame: ch,
                mBitsPerChannel: 0,
                mReserved: 0
            )
            let bytesPerFrame = ch * 2
            var dstFormat = AudioStreamBasicDescription(
                mSampleRate: rate,
                mFormatID: kAudioFormatLinearPCM,
                mFormatFlags: kLinearPCMFormatFlagIsSignedInteger | kLinearPCMFormatFlagIsPacked,
                mBytesPerPacket: bytesPerFrame,
                mFramesPerPacket: 1,
                mBytesPerFrame: bytesPerFrame,
                mChannelsPerFrame: ch,
                mBitsPerChannel: 16,
                mReserved: 0
            )
            var created: AudioConverterRef?
            let status = AudioConverterNew(&srcFormat, &dstFormat, &created)
            guard status == noErr, let created else {
                return nil
            }
            self.converter = created
            self.configuredChannels = ch
            self.configuredSampleRate = rate
        }

        guard let activeConverter = converter else { return nil }
        let bytesPerFrame = Int(ch) * 2
        let maxOutBytes = Int(Self.maxDecodedFramesPerPacket) * bytesPerFrame
        if decodeScratch.count < maxOutBytes {
            decodeScratch = [UInt8](repeating: 0, count: maxOutBytes)
        }

        return opusPacket.withUnsafeBytes { rawInput -> Data? in
            guard let inputBase = rawInput.baseAddress else { return nil }
            inputContext.packetBytes = inputBase
            inputContext.packetLength = opusPacket.count
            inputContext.packetDesc = AudioStreamPacketDescription(
                mStartOffset: 0,
                mVariableFramesInPacket: 0,
                mDataByteSize: UInt32(opusPacket.count)
            )
            inputContext.consumed = false

            return decodeScratch.withUnsafeMutableBytes { rawOut -> Data? in
                guard let outBase = rawOut.baseAddress else { return nil }
                var outBufferList = AudioBufferList(
                    mNumberBuffers: 1,
                    mBuffers: AudioBuffer(
                        mNumberChannels: ch,
                        mDataByteSize: UInt32(maxOutBytes),
                        mData: outBase
                    )
                )
                var ioOutputDataPackets = Self.maxDecodedFramesPerPacket
                let callback: AudioConverterComplexInputDataProc = { _, ioNumberDataPackets, ioData, outDataPacketDescription, userData in
                    guard let userData else {
                        ioNumberDataPackets.pointee = 0
                        return -50
                    }
                    let ctx = Unmanaged<InputContext>.fromOpaque(userData).takeUnretainedValue()
                    if ctx.consumed {
                        ioNumberDataPackets.pointee = 0
                        ioData.pointee.mBuffers.mData = nil
                        ioData.pointee.mBuffers.mDataByteSize = 0
                        return AppleOpusAudioDecoder.endOfSinglePacketStatus
                    }
                    ctx.consumed = true
                    ioNumberDataPackets.pointee = 1
                    ioData.pointee.mBuffers.mData = UnsafeMutableRawPointer(mutating: ctx.packetBytes)
                    ioData.pointee.mBuffers.mDataByteSize = UInt32(ctx.packetLength)
                    if let outDataPacketDescription {
                        withUnsafeMutablePointer(to: &ctx.packetDesc) { descPtr in
                            outDataPacketDescription.pointee = descPtr
                        }
                    }
                    return noErr
                }

                let status = AudioConverterFillComplexBuffer(
                    activeConverter,
                    callback,
                    Unmanaged.passUnretained(inputContext).toOpaque(),
                    &ioOutputDataPackets,
                    &outBufferList,
                    nil
                )
                guard status == noErr || status == Self.endOfSinglePacketStatus else {
                    return nil
                }
                let decodedFrames = Int(ioOutputDataPackets)
                let producedBytes = min(decodedFrames * bytesPerFrame, Int(outBufferList.mBuffers.mDataByteSize))
                guard producedBytes > 0, producedBytes % bytesPerFrame == 0 else {
                    return nil
                }
                return Data(bytes: outBase, count: producedBytes)
            }
        }
    }
}
#endif

/// Control-channel JSON message exchanged over authenticated mTLS TCP to set up
/// a session-scoped UDP media plane.
struct UDPMediaConfigMessage: Equatable, Sendable {
    var sessionEpoch: Int64
    var udpPort: UInt16
    var rootSecretBase64: String
    var maxPayloadBytes: Int = UDPMediaHeader.maxPayloadLength

    var jsonObject: [String: Any] {
        [
            "type": "udpMediaConfig",
            "version": Int(UDPMediaHeader.currentVersion),
            "sessionEpoch": sessionEpoch,
            "udpPort": Int(udpPort),
            "rootSecret": rootSecretBase64,
            "maxPayloadBytes": maxPayloadBytes,
        ]
    }

    var jsonString: String {
        "{\"type\":\"udpMediaConfig\","
            + "\"version\":\(UDPMediaHeader.currentVersion),"
            + "\"sessionEpoch\":\(sessionEpoch),"
            + "\"udpPort\":\(udpPort),"
            + "\"rootSecret\":\"\(rootSecretBase64)\","
            + "\"maxPayloadBytes\":\(maxPayloadBytes)}"
    }

    init(sessionEpoch: Int64, udpPort: UInt16, rootSecret: Data, maxPayloadBytes: Int = UDPMediaHeader.maxPayloadLength) {
        self.sessionEpoch = sessionEpoch
        self.udpPort = udpPort
        self.rootSecretBase64 = rootSecret.base64EncodedString()
        self.maxPayloadBytes = maxPayloadBytes
    }

    init?(jsonObject: [String: Any]) {
        guard (jsonObject["type"] as? String) == "udpMediaConfig",
              let version = jsonObject["version"] as? Int,
              version == Int(UDPMediaHeader.currentVersion),
              let port = jsonObject["udpPort"] as? Int,
              (1...65535).contains(port),
              let secretString = jsonObject["rootSecret"] as? String,
              let secretData = Data(base64Encoded: secretString),
              secretData.count == UDPMediaKeyMaterial.rootSecretByteLength else {
            return nil
        }
        let epoch: Int64
        if let e = jsonObject["sessionEpoch"] as? Int64 {
            epoch = e
        } else if let e = jsonObject["sessionEpoch"] as? Int {
            epoch = Int64(e)
        } else if let num = jsonObject["sessionEpoch"] as? NSNumber {
            epoch = num.int64Value
        } else {
            return nil
        }
        guard epoch > 0 else { return nil }
        self.sessionEpoch = epoch
        self.udpPort = UInt16(port)
        self.rootSecretBase64 = secretString
        self.maxPayloadBytes = min(
            max((jsonObject["maxPayloadBytes"] as? Int) ?? UDPMediaHeader.maxPayloadLength, 512),
            UDPMediaHeader.maxPayloadLength
        )
    }

    var rootSecretData: Data? {
        Data(base64Encoded: rootSecretBase64)
    }
}

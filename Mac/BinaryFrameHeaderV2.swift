import Foundation

enum BinaryFrameHeaderV2 {
    static let version: UInt8 = 2
    static let headerLength = 52
    // The existing outer length includes this header and remains capped at
    // 16 MiB, so reserve the header bytes inside that same safety bound.
    static let maximumPayloadBytes = 16 * 1_024 * 1_024 - headerLength
    private static let magic: [UInt8] = [0x44, 0x57, 0x56, 0x32] // DWV2

    struct Flags: OptionSet, Equatable, Sendable {
        let rawValue: UInt8

        static let keyframe = Flags(rawValue: 1 << 0)
        static let codecConfig = Flags(rawValue: 1 << 1)
        static let hevc = Flags(rawValue: 1 << 2)
        static let h264 = Flags(rawValue: 1 << 3)
        static let known: Flags = [.keyframe, .codecConfig, .hevc, .h264]
    }

    enum Error: Swift.Error, Equatable {
        case notBinary
        case truncatedHeader
        case unknownVersion
        case invalidHeaderLength
        case invalidFlags
        case invalidIdentity
        case invalidPayloadLength
        case oversizePayload
    }

    struct Decoded: Equatable {
        let headerLength: Int
        let flags: Flags
        let identity: StreamProtocolFrameIdentity
        let captureTimestampMs: Int64
        let sendTimestampMs: Int64
        let payload: Data
    }

    static func encode(
        payload: Data,
        flags: Flags,
        identity: StreamProtocolFrameIdentity,
        captureTimestampMs: Int64,
        sendTimestampMs: Int64
    ) throws -> Data {
        try validate(
            flags: flags,
            identity: identity,
            captureTimestampMs: captureTimestampMs,
            sendTimestampMs: sendTimestampMs,
            payloadLength: payload.count)
        var frame = Data(capacity: headerLength + payload.count)
        frame.append(contentsOf: magic)
        frame.append(version)
        frame.append(flags.rawValue)
        append(UInt16(headerLength), to: &frame)
        append(UInt64(identity.sessionEpoch), to: &frame)
        append(UInt64(identity.configVersion), to: &frame)
        append(UInt64(identity.frameSequence), to: &frame)
        append(UInt64(captureTimestampMs), to: &frame)
        append(UInt64(sendTimestampMs), to: &frame)
        append(UInt32(payload.count), to: &frame)
        frame.append(payload)
        return frame
    }

    static func decode(_ frame: Data) throws -> Decoded {
        guard frame.count >= 4, Array(frame.prefix(4)) == magic else {
            throw Error.notBinary
        }
        guard frame.count >= headerLength else { throw Error.truncatedHeader }
        guard frame[4] == version else { throw Error.unknownVersion }
        let flags = Flags(rawValue: frame[5])
        let decodedHeaderLength = Int(readUInt16(frame, at: 6))
        guard decodedHeaderLength == headerLength else {
            throw Error.invalidHeaderLength
        }
        let epoch = readUInt64(frame, at: 8)
        let config = readUInt64(frame, at: 16)
        let sequence = readUInt64(frame, at: 24)
        let capture = readUInt64(frame, at: 32)
        let send = readUInt64(frame, at: 40)
        let payloadLength = Int(readUInt32(frame, at: 48))
        guard epoch <= UInt64(Int64.max), config <= UInt64(Int64.max),
              sequence <= UInt64(Int64.max), capture <= UInt64(Int64.max),
              send <= UInt64(Int64.max) else {
            throw Error.invalidIdentity
        }
        let identity = StreamProtocolFrameIdentity(
            sessionEpoch: Int64(epoch),
            configVersion: Int64(config),
            frameSequence: Int64(sequence))
        try validate(
            flags: flags,
            identity: identity,
            captureTimestampMs: Int64(capture),
            sendTimestampMs: Int64(send),
            payloadLength: payloadLength)
        guard decodedHeaderLength + payloadLength == frame.count else {
            throw Error.invalidPayloadLength
        }
        return Decoded(
            headerLength: decodedHeaderLength,
            flags: flags,
            identity: identity,
            captureTimestampMs: Int64(capture),
            sendTimestampMs: Int64(send),
            payload: frame.subdata(in: decodedHeaderLength..<frame.count))
    }

    private static func validate(
        flags: Flags,
        identity: StreamProtocolFrameIdentity,
        captureTimestampMs: Int64,
        sendTimestampMs: Int64,
        payloadLength: Int
    ) throws {
        let unknown = flags.rawValue & ~Flags.known.rawValue
        let hasHevc = flags.contains(.hevc)
        let hasH264 = flags.contains(.h264)
        guard unknown == 0, hasHevc != hasH264 else { throw Error.invalidFlags }
        guard identity.sessionEpoch > 0, identity.configVersion > 0,
              identity.frameSequence > 0, captureTimestampMs >= 0,
              sendTimestampMs >= 0 else {
            throw Error.invalidIdentity
        }
        guard payloadLength > 0 else { throw Error.invalidPayloadLength }
        guard payloadLength <= maximumPayloadBytes else { throw Error.oversizePayload }
    }

    private static func append<T: FixedWidthInteger>(_ value: T, to data: inout Data) {
        var bigEndian = value.bigEndian
        withUnsafeBytes(of: &bigEndian) { data.append(contentsOf: $0) }
    }

    private static func readUInt16(_ data: Data, at offset: Int) -> UInt16 {
        (UInt16(data[offset]) << 8) | UInt16(data[offset + 1])
    }

    private static func readUInt32(_ data: Data, at offset: Int) -> UInt32 {
        (0..<4).reduce(UInt32(0)) { ($0 << 8) | UInt32(data[offset + $1]) }
    }

    private static func readUInt64(_ data: Data, at offset: Int) -> UInt64 {
        (0..<8).reduce(UInt64(0)) { ($0 << 8) | UInt64(data[offset + $1]) }
    }
}

enum VideoFrameWirePayload {
    static func encode(
        annexB: Data,
        codec: StreamCodec,
        isKeyframe: Bool,
        captureTimestampMs: Int64,
        sendTimestampMs: Int64,
        identity: StreamProtocolFrameIdentity?,
        binaryHeaderEnabled: Bool
    ) throws -> Data {
        if binaryHeaderEnabled, let identity {
            var flags: BinaryFrameHeaderV2.Flags = codec == .hevc
                ? [.hevc] : [.h264]
            if isKeyframe {
                flags.formUnion([.keyframe, .codecConfig])
            }
            return try BinaryFrameHeaderV2.encode(
                payload: annexB,
                flags: flags,
                identity: identity,
                captureTimestampMs: captureTimestampMs,
                sendTimestampMs: sendTimestampMs)
        }
        let prefix = VideoTelemetryPrefix.json(
            captureMs: captureTimestampMs,
            sendMs: sendTimestampMs,
            identity: identity)
        var legacy = Data(prefix.utf8)
        legacy.append(annexB)
        return legacy
    }
}

import Foundation

func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() { fatalError(message) }
}

@main
struct BinaryFrameHeaderV2SelfTest {
    static func main() throws {
        let identity = StreamProtocolFrameIdentity(
            sessionEpoch: 8, configVersion: 12, frameSequence: 44)
        let payload = Data([0, 0, 0, 1, 0x65, 1, 2, 3])
        let encoded = try BinaryFrameHeaderV2.encode(
            payload: payload,
            flags: [.keyframe, .codecConfig, .h264],
            identity: identity,
            captureTimestampMs: 1_000,
            sendTimestampMs: 1_010)
        let decoded = try BinaryFrameHeaderV2.decode(encoded)

        expect(Array(encoded.prefix(4)) == [0x44, 0x57, 0x56, 0x32],
               "wire magic is DWV2")
        expect(encoded[4] == 2, "wire version is two")
        expect(decoded.headerLength == 52, "fixed header length")
        expect(decoded.identity == identity, "identity round trips")
        expect(decoded.captureTimestampMs == 1_000, "capture timestamp round trips")
        expect(decoded.sendTimestampMs == 1_010, "send timestamp round trips")
        expect(decoded.flags.contains(.keyframe), "keyframe flag round trips")
        expect(decoded.flags.contains(.codecConfig), "codec-config flag round trips")
        expect(decoded.flags.contains(.h264) && !decoded.flags.contains(.hevc),
               "codec flag round trips")
        expect(decoded.payload == payload, "payload round trips")

        let legacy = try VideoFrameWirePayload.encode(
            annexB: payload, codec: .h264, isKeyframe: true,
            captureTimestampMs: 1_000, sendTimestampMs: 1_010,
            identity: nil, binaryHeaderEnabled: false)
        let expectedLegacy = Data("{\"cap\":1000,\"snd\":1010}".utf8) + payload
        expect(legacy == expectedLegacy,
               "Legacy iOS framing remains byte-for-byte unchanged")

        let coreV2WithoutBinary = try VideoFrameWirePayload.encode(
            annexB: payload, codec: .h264, isKeyframe: true,
            captureTimestampMs: 1_000, sendTimestampMs: 1_010,
            identity: identity, binaryHeaderEnabled: false)
        expect(coreV2WithoutBinary.starts(with: Data("{\"cap\":".utf8)),
               "core V2 without the independent capability keeps JSON telemetry")

        let negotiatedBinary = try VideoFrameWirePayload.encode(
            annexB: payload, codec: .h264, isKeyframe: true,
            captureTimestampMs: 1_000, sendTimestampMs: 1_010,
            identity: identity, binaryHeaderEnabled: true)
        expect(Array(negotiatedBinary.prefix(4)) == [0x44, 0x57, 0x56, 0x32],
               "independent capability selects DWV2 framing")

        var unknownVersion = encoded
        unknownVersion[4] = 3
        do {
            _ = try BinaryFrameHeaderV2.decode(unknownVersion)
            fatalError("unknown version must fail")
        } catch BinaryFrameHeaderV2.Error.unknownVersion {
        }

        var conflictingCodec = encoded
        conflictingCodec[5] |= BinaryFrameHeaderV2.Flags.hevc.rawValue
        do {
            _ = try BinaryFrameHeaderV2.decode(conflictingCodec)
            fatalError("conflicting codec flags must fail")
        } catch BinaryFrameHeaderV2.Error.invalidFlags {
        }

        print("BinaryFrameHeaderV2SelfTest PASS")
    }
}

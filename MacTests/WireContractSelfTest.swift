import Foundation

@main enum WireContractSelfTest {
    static func main() throws {
        let sent = StreamDebugStats(droppedFramesMac: 9, queueDepthMac: 2, pendingEncodesMac: 1,
            totalPendingWorkMac: 3, pendingEncodePeak: 2, captureFps: 60, requestedFps: 60,
            actualVirtualDisplayRefreshRate: 60, encodedFps: 60, sentFps: 60,
            averageFrameSize: 1000, encodeLatencyMs: 2, bitrate: 40_000_000,
            inputP50Ms: 0, inputP95Ms: 0)
        let ping = try JSONSerialization.jsonObject(with: Data(sent.pingJson(nowMs: 1).utf8)) as! [String: Any]
        let health = SenderHealthTelemetry(ping)
        precondition(health.droppedFrames == 9 && health.queueDepth == 2)
        let legacyHealth = SenderHealthTelemetry(["drops": 4, "pending": 1])
        precondition(legacyHealth.droppedFrames == 4 && legacyHealth.queueDepth == 1)
        precondition(SenderHealthTelemetry(["droppedFramesMac": 0, "drops": 4]).droppedFrames == 0)
        precondition(SenderHealthTelemetry(["pending": -1]).queueDepth == nil)
        let text = try String(contentsOfFile: "tools/fixtures/wire-contract-v1.properties", encoding: .utf8)
        let fixtures = Dictionary(uniqueKeysWithValues: text.split(separator: "\n").compactMap { line -> (String, String)? in
            guard !line.hasPrefix("#") else { return nil }
            let parts = line.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            return parts.count == 2 ? (String(parts[0]), String(parts[1])) : nil
        })
        func hex(_ key: String) -> Data {
            let value = Array(fixtures[key]!.utf8)
            return Data(stride(from: 0, to: value.count, by: 2).map { UInt8(String(decoding: value[$0..<$0+2], as: UTF8.self), radix: 16)! })
        }
        for name in ["ping", "legacy", "h264", "hevc", "desktop", "pencil", "action"] {
            let payload = hex(name + "Payload"), framed = hex(name + "Frame")
            precondition(ReceiverFrameDecoder.frame(payload) == framed)
            // Every boundary is exercised: TCP splits headers and bodies arbitrarily.
            for split in 0...framed.count {
                var decoder = ReceiverFrameDecoder()
                let frames = try decoder.append(Data(framed.prefix(split))) + decoder.append(Data(framed.dropFirst(split)))
                precondition(frames == [payload], "fragmented fixture \(name)")
            }
            var decoder = ReceiverFrameDecoder()
            let coalesced = try decoder.append(framed + framed)
            precondition(coalesced == [payload, payload])
        }
        for name in ["zero", "oversize", "negative"] {
            var decoder = ReceiverFrameDecoder()
            do { _ = try decoder.append(hex(name)); preconditionFailure("invalid length accepted") }
            catch ReceiverFrameDecoder.Failure.invalidLength { }
        }
        for name in ["h264", "hevc"] {
            let decoded = try BinaryFrameHeaderV2.decode(hex(name + "Payload"))
            let encoded = try BinaryFrameHeaderV2.encode(payload: decoded.payload, flags: decoded.flags,
                identity: decoded.identity, captureTimestampMs: decoded.captureTimestampMs, sendTimestampMs: decoded.sendTimestampMs)
            precondition(encoded == hex(name + "Payload"))
            precondition(decoded.identity == StreamProtocolFrameIdentity(sessionEpoch: 8, configVersion: 12, frameSequence: name == "h264" ? 44 : 45))
        }
        for name in ["badVersion", "badFlags", "badIdentity", "badPayloadLength", "truncatedBinary"] {
            do { _ = try BinaryFrameHeaderV2.decode(hex(name)); preconditionFailure("invalid DWV2 accepted") }
            catch is BinaryFrameHeaderV2.Error { }
        }
        let legacy = try VideoFrameWirePayload.encode(annexB: hex("annexB"), codec: .h264, isKeyframe: true,
            captureTimestampMs: 1000, sendTimestampMs: 1010, identity: nil, binaryHeaderEnabled: false)
        precondition(legacy == hex("legacyPayload"))
        precondition(DesktopInputEvent.decode(hex("desktopPayload"))?.sequence == 1)
        precondition(DesktopInputEvent.decode(hex("badDesktopPayload")) == nil)
        let pencil = try JSONSerialization.jsonObject(with: hex("pencilPayload")) as! [String: Any]
        precondition(PencilSample(message: pencil)?.tool == .eraser)
        precondition(PencilSample(message: pencil)?.roll == 1.5)
        precondition(PencilActionMessage(hex("actionPayload"))?.action == .undo)
        precondition(PencilActionMessage(hex("badActionPayload")) == nil)
        print("Shared wire fixtures: Swift framing/fragmentation, DWV2, legacy bytes and Apple input contracts PASS")
    }
}

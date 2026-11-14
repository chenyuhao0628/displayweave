import Foundation

private func expect(_ condition: @autoclosure () throws -> Bool, _ message: String) {
    do {
        if !(try condition()) { fatalError(message) }
    } catch {
        fatalError("\(message): \(error)")
    }
}

@main
struct UDPMediaProtocolSelfTest {
    static func main() throws {
        // 1. Exact 16-byte header layout and round-trip
        let header = UDPMediaHeader(
            packetType: .videoData,
            flags: [.keyframe, .endOfFrame],
            epochTag: 0x42,
            packetSeq: 65534,
            sendTimeUs: 123_456_789,
            frameId: 9_876,
            fragIndex: 3,
            fragCount: 4
        )
        let encodedHeader = header.encode()
        expect(encodedHeader.count == 16, "UDPMediaHeader must be exactly 16 bytes")
        let decodedHeader = try UDPMediaHeader.decode(from: encodedHeader)
        expect(decodedHeader == header, "16-byte header must round-trip losslessly")

        // Reject invalid fragment bounds on videoData
        var badFrag = encodedHeader
        badFrag[12] = 0x00; badFrag[13] = 0x05 // fragIndex 5 >= fragCount 4
        do {
            _ = try UDPMediaHeader.decode(from: badFrag)
            fatalError("expected invalidFragmentBounds")
        } catch let error as UDPMediaError {
            expect(error == .invalidFragmentBounds, "fragIndex >= fragCount must fail")
        }

        // 2. Deterministic HKDF-SHA256 key derivation with golden vector check
        let fixedSecret = Data((0..<32).map { UInt8($0 + 1) })
        let keysEpoch1 = try UDPMediaKeyMaterial.derive(rootSecret: fixedSecret, sessionEpoch: 1)
        let keysEpoch2 = try UDPMediaKeyMaterial.derive(rootSecret: fixedSecret, sessionEpoch: 2)
        expect(keysEpoch1.senderToReceiverKey.count == 16 && keysEpoch1.senderToReceiverSalt.count == 12,
               "s2r key must be 16B and salt 12B")
        expect(keysEpoch1.receiverToSenderKey.count == 16 && keysEpoch1.receiverToSenderSalt.count == 12,
               "r2s key must be 16B and salt 12B")
        expect(keysEpoch1.senderToReceiverKey != keysEpoch1.receiverToSenderKey,
               "directional keys must be cryptographically separated")
        expect(keysEpoch1.senderToReceiverKey != keysEpoch2.senderToReceiverKey,
               "different sessionEpochs must derive distinct keys")

        // 3. Per-packet AES-128-GCM, AAD header authentication, 1024-packet anti-replay, and 64-bit ROC rollover
        var sender = UDPMediaCryptoSession(keyMaterial: keysEpoch1)
        var receiver = UDPMediaCryptoSession(keyMaterial: keysEpoch1)

        let payload = Data("DisplayWeave-UDP-Fragment-Payload".utf8)
        let (datagram1, _, seq1) = try sender.seal(
            direction: .senderToReceiver,
            packetType: .videoData,
            flags: [.keyframe],
            sendTimeUs: 1000,
            frameId: 1,
            fragIndex: 0,
            fragCount: 2,
            payload: payload
        )
        expect(seq1 == 1, "first outgoing sequence is 1")
        expect(datagram1.count == 16 + payload.count + 16, "datagram = 16B header + payload + 16B GCM tag")

        // Tampering with AAD header (e.g. changing fragIndex or flags) must fail authentication
        // AND must not mutate receiver anti-replay window!
        var tamperedHeaderDatagram = datagram1
        tamperedHeaderDatagram[0] ^= 0x01 // flip keyframe flag in AAD
        do {
            _ = try receiver.open(datagram: tamperedHeaderDatagram, expectedDirection: .senderToReceiver)
            fatalError("tampered AAD header must not authenticate")
        } catch let error as UDPMediaError {
            expect(error == .authenticationFailed, "tampered AAD must throw authenticationFailed")
        }
        expect(!receiver.replayWindow.hasAuthenticatedAny,
               "unauthenticated packet must not pollute anti-replay state")

        // Genuine packet authenticates and records sequence 1
        let opened1 = try receiver.open(datagram: datagram1, expectedDirection: .senderToReceiver)
        expect(opened1.payload == payload && opened1.extendedSequence == 1,
               "genuine packet opens and yields extendedSequence 1")

        // Immediate replay of datagram1 is rejected before decryption
        do {
            _ = try receiver.open(datagram: datagram1, expectedDirection: .senderToReceiver)
            fatalError("duplicate packet must be rejected")
        } catch let error as UDPMediaError {
            expect(error == .replayRejected, "duplicate packet must throw replayRejected")
        }

        // Out-of-order delivery within 1024-packet window AND across 16-bit sequence wrap-around (65535 -> 65536 -> 65537)
        var delayedDatagram: Data?
        for i in 2...65540 {
            let (dg, _, seq) = try sender.seal(
                direction: .senderToReceiver,
                packetType: .videoData,
                flags: [.endOfFrame],
                sendTimeUs: UInt32(i * 100),
                frameId: UInt32(i),
                fragIndex: 0,
                fragCount: 1,
                payload: Data([UInt8(i & 0xFF)])
            )
            expect(seq == UInt64(i), "monotonic extended sequence tracks across 16-bit wrap")
            if i == 65500 {
                delayedDatagram = dg // hold back packet 65500 while crossing 65536 wrap
                continue
            }
            let opened = try receiver.open(datagram: dg, expectedDirection: .senderToReceiver)
            expect(opened.extendedSequence == UInt64(i),
                   "64-bit ROC reconstructs extended sequence \(i) across 65536 wrap")
        }
        // Now deliver held-back packet 65500 (age = 65540 - 65500 = 40 < 1024, across 16-bit boundary!)
        let recoveredDelayed = try receiver.open(datagram: delayedDatagram!, expectedDirection: .senderToReceiver)
        expect(recoveredDelayed.extendedSequence == 65500,
               "delayed packet from before 16-bit wrap opens with exact 64-bit sequence 65500")

        // NACK and Feedback payload round-trip
        let nack = UDPMediaNackPayload(
            frameId: 42,
            baseFragIndex: 10,
            missingCount: 2,
            missingBitmap: (1 << 0) | (1 << 3),
            rttEstimateUs: 8_500
        )
        let decodedNack = try UDPMediaNackPayload.decode(from: nack.encode())
        expect(decodedNack == nack, "NACK payload round-trips")
        expect(decodedNack.missingFragmentIndices(maxFragCount: 20) == [10, 13],
               "NACK bitmap extracts missing fragment indices")

        let feedback = UDPMediaFeedbackPayload(
            highestSeq: 65540,
            receivedCount: 120,
            lostCount: 2,
            arrivalGradientUs: -450,
            decodeQueueMs: 4,
            renderFps: 60,
            echoSendTimeUs: 999_111
        )
        let decodedFeedback = try UDPMediaFeedbackPayload.decode(from: feedback.encode())
        expect(decodedFeedback == feedback, "Feedback payload round-trips including signed arrivalGradientUs")

        // Control negotiation JSON round-trip
        let rootSecret = UDPMediaKeyMaterial.generateRootSecret()
        let configMsg = UDPMediaConfigMessage(sessionEpoch: 7, udpPort: 51820, rootSecret: rootSecret)
        let parsedJson = try JSONSerialization.jsonObject(with: Data(configMsg.jsonString.utf8)) as! [String: Any]
        let parsedConfig = UDPMediaConfigMessage(jsonObject: parsedJson)
        expect(parsedConfig == configMsg && parsedConfig?.rootSecretData == rootSecret,
               "UDPMediaConfigMessage serializes and parses 32-byte rootSecret losslessly")

        // 4. Modular 32-bit frameId wrap-safe comparison
        expect(UDPMediaHeader.isFrameIdNewer(0, than: 0xFFFF_FFFF), "0 is newer than UInt32.max across wrap")
        expect(UDPMediaHeader.isFrameIdNewer(5, than: 0xFFFF_FFFE), "5 is newer than UInt32.max - 1 across wrap")
        expect(!UDPMediaHeader.isFrameIdNewer(0xFFFF_FFFE, than: 2), "older wrapped frameId is not newer")
        expect(UDPMediaHeader.frameIdDelta(2, 0xFFFF_FFFF) == 3, "signed modular delta across UInt32 wrap")

        // 6. Golden vector byte-for-byte parity check against tools/fixtures/wire-contract-v1.properties
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let fixturePath = FileManager.default.fileExists(atPath: "tools/fixtures/wire-contract-v1.properties")
            ? "tools/fixtures/wire-contract-v1.properties"
            : repoRoot.appendingPathComponent("tools/fixtures/wire-contract-v1.properties").path
        let fixtureText = try String(contentsOfFile: fixturePath, encoding: .utf8)
        let fixtures = Dictionary(uniqueKeysWithValues: fixtureText.split(separator: "\n").compactMap { line -> (String, String)? in
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { return nil }
            let parts = trimmed.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            return parts.count == 2 ? (String(parts[0]), String(parts[1])) : nil
        })
        func fixtureHex(_ key: String) -> Data {
            guard let raw = fixtures[key] else { fatalError("missing fixture key \(key)") }
            let utf8 = Array(raw.utf8)
            expect(utf8.count % 2 == 0, "even hex length for \(key)")
            return Data(stride(from: 0, to: utf8.count, by: 2).map {
                UInt8(String(decoding: utf8[$0..<($0 + 2)], as: UTF8.self), radix: 16)!
            })
        }

        expect(fixtureHex("udpRootSecret") == fixedSecret, "udpRootSecret matches bytes 01..20")
        expect(keysEpoch1.senderToReceiverKey == fixtureHex("udpS2RKeyEpoch1"), "HKDF s2r key matches golden vector")
        expect(keysEpoch1.senderToReceiverSalt == fixtureHex("udpS2RSaltEpoch1"), "HKDF s2r salt matches golden vector")
        expect(keysEpoch1.receiverToSenderKey == fixtureHex("udpR2SKeyEpoch1"), "HKDF r2s key matches golden vector")
        expect(keysEpoch1.receiverToSenderSalt == fixtureHex("udpR2SSaltEpoch1"), "HKDF r2s salt matches golden vector")
        expect(keysEpoch1.nonce(for: .senderToReceiver, extendedSequence: 1) == fixtureHex("udpS2RNonceSeq1"),
               "s2r nonce seq=1 matches golden vector")
        expect(keysEpoch1.nonce(for: .receiverToSender, extendedSequence: 1) == fixtureHex("udpR2SNonceSeq1"),
               "r2s nonce seq=1 matches golden vector")

        let expectedVideoHdr = UDPMediaHeader(
            packetType: .videoData,
            flags: [.keyframe, .endOfFrame],
            epochTag: 1,
            packetSeq: 42,
            sendTimeUs: 123_456,
            frameId: 7,
            fragIndex: 0,
            fragCount: 1
        )
        expect(expectedVideoHdr.encode() == fixtureHex("udpHeaderVideoData"), "udpHeaderVideoData matches golden vector")

        print("UDPMediaProtocolSelfTest PASS")
    }
}

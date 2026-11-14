import Foundation

private func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() { fatalError(message) }
}

@main
struct UDPMediaEngineSelfTest {
    static func main() throws {
        let secret = UDPMediaKeyMaterial.generateRootSecret()
        let keys = try UDPMediaKeyMaterial.derive(rootSecret: secret, sessionEpoch: 11)
        var senderCrypto = UDPMediaCryptoSession(keyMaterial: keys)
        var receiverCrypto = UDPMediaCryptoSession(keyMaterial: keys)

        // 1. Fragmentation & Early Data-Complete Submission (without waiting for FEC parity)
        let annexB = Data((0..<3000).map { UInt8($0 & 0xFF) })
        let dataShards = try UDPMediaFramePacketizer.makeDataFragments(
            annexB: annexB,
            captureTimestampMs: 1_700_000_000_123,
            configVersion: 2
        )
        expect(dataShards.count == 3, "3000B Annex-B + 16B metadata splits into 3 fragments of <=1200B")

        var reassembler = UDPMediaReassembler()
        var completedFrame: UDPMediaFrameEnvelope?
        for (idx, shard) in dataShards.enumerated() {
            var flags: UDPMediaFlags = [.keyframe]
            if idx == dataShards.count - 1 { flags.insert(.endOfFrame) }
            let (dg, _, _) = try senderCrypto.seal(
                direction: .senderToReceiver,
                packetType: .videoData,
                flags: flags,
                sendTimeUs: 5000,
                frameId: 1,
                fragIndex: UInt16(idx),
                fragCount: UInt16(dataShards.count),
                payload: shard
            )
            let auth = try receiverCrypto.open(datagram: dg, expectedDirection: .senderToReceiver)
            completedFrame = reassembler.ingest(packet: auth, nowMonoNs: 1_000_000)
        }
        expect(completedFrame != nil, "all data shards arriving must submit immediately without waiting for parity")
        expect(completedFrame?.annexB == annexB
                && completedFrame?.captureTimestampMs == 1_700_000_000_123
                && completedFrame?.configVersion == 2
                && completedFrame?.recoveredByFEC == false,
               "reassembled frame preserves exact Annex-B, captureTimestampMs, and configVersion")

        // 2. FEC Recovery in Reassembler when middle fragment is lost
        let parityShards = UDPMediaFECEncoder.encodeParityShards(
            dataShards: dataShards,
            lossFraction: 0.05,
            isKeyframe: false
        )
        expect(!parityShards.isEmpty, "FEC parity shard generated")
        for (idx, shard) in dataShards.enumerated() {
            if idx == 1 { continue } // Drop middle data fragment!
            let (dg, _, _) = try senderCrypto.seal(
                direction: .senderToReceiver,
                packetType: .videoData,
                flags: idx == dataShards.count - 1 ? [.endOfFrame] : [],
                sendTimeUs: 6000,
                frameId: 2,
                fragIndex: UInt16(idx),
                fragCount: UInt16(dataShards.count),
                payload: shard
            )
            let auth = try receiverCrypto.open(datagram: dg, expectedDirection: .senderToReceiver)
            expect(reassembler.ingest(packet: auth, nowMonoNs: 2_000_000) == nil,
                   "frame 2 is incomplete while fragment 1 is missing")
        }
        // Now deliver the parity shard for frame 2 — it must immediately recover fragment 1 and emit frame 2!
        let firstParity = parityShards[0]
        let (parityDg, _, _) = try senderCrypto.seal(
            direction: .senderToReceiver,
            packetType: .videoParity,
            flags: [],
            sendTimeUs: 6000,
            frameId: 2,
            fragIndex: firstParity.descriptor.encodedFragIndex,
            fragCount: firstParity.descriptor.encodedFragCount,
            payload: firstParity.payload
        )
        let authParity = try receiverCrypto.open(datagram: parityDg, expectedDirection: .senderToReceiver)
        let fecFrame = reassembler.ingest(packet: authParity, nowMonoNs: 2_500_000)
        expect(fecFrame != nil && fecFrame?.recoveredByFEC == true && fecFrame?.annexB == annexB,
               "Reassembler recovers missing fragment 1 via FEC parity shard and delivers complete frame 2")

        // 3. NACK bitmap generation + Sender Retransmit Cache
        var rtxCache = UDPRetransmitCache()
        for (idx, shard) in dataShards.enumerated() {
            rtxCache.store(
                frameId: 3,
                fragIndex: UInt16(idx),
                fragCount: UInt16(dataShards.count),
                flags: [],
                payload: shard,
                nowUptime: 10.0
            )
            if idx == 2 { continue } // Drop fragment 2 of frame 3
            let (dg, _, _) = try senderCrypto.seal(
                direction: .senderToReceiver,
                packetType: .videoData,
                flags: [],
                sendTimeUs: 7000,
                frameId: 3,
                fragIndex: UInt16(idx),
                fragCount: UInt16(dataShards.count),
                payload: shard
            )
            let auth = try receiverCrypto.open(datagram: dg, expectedDirection: .senderToReceiver)
            _ = reassembler.ingest(packet: auth, nowMonoNs: 10_000_000)
        }
        // Before max(2ms, RTT/2), pollNacks returns empty
        expect(reassembler.pollNacks(nowMonoNs: 11_000_000, rttUs: 8_000).isEmpty,
               "must wait max(2ms, RTT/2) before emitting NACK")
        let nacks = reassembler.pollNacks(nowMonoNs: 15_000_000, rttUs: 8_000)
        expect(nacks.count == 1 && nacks[0].frameId == 3 && nacks[0].missingFragmentIndices(maxFragCount: 3) == [2],
               "pollNacks emits bitmap identifying missing fragment 2 of frame 3")
        let rtxEntries = rtxCache.consumeForRetransmit(nack: nacks[0], nowUptime: 10.005)
        expect(rtxEntries.count == 1 && rtxEntries[0].fragIndex == 2,
               "Retransmit cache yields missing fragment 2 once")
        expect(rtxCache.consumeForRetransmit(nack: nacks[0], nowUptime: 10.006).isEmpty,
               "Retransmit cache enforces at-most-once retransmission per fragment")

        // 4. Debt-Based Pacer priority ordering & stale P-frame purge on new IDR
        var pacer = UDPDebtPacer(targetBitrateBps: 40_000_000)
        let dummyData = Data(repeating: 0xAA, count: 1000)
        pacer.enqueueFrameDatagrams([
            UDPQueuedDatagram(priority: .normalVideo, frameId: 10, fragIndex: 0, isParity: false, datagram: dummyData),
            UDPQueuedDatagram(priority: .fecParity, frameId: 10, fragIndex: 0, isParity: true, datagram: dummyData),
        ], isKeyframe: false, frameId: 10)
        // Enqueue a new keyframe (frameId 11) and a retransmit (frameId 9)
        pacer.enqueueFrameDatagrams([
            UDPQueuedDatagram(priority: .keyframe, frameId: 11, fragIndex: 0, isParity: false, datagram: dummyData),
        ], isKeyframe: true, frameId: 11)
        pacer.enqueueRetransmit(
            UDPQueuedDatagram(priority: .retransmit, frameId: 9, fragIndex: 1, isParity: false, datagram: dummyData)
        )
        expect(pacer.purgedStaleFragments == 2,
               "new keyframe must purge queued unsent normalVideo and fecParity fragments from frame 10")
        let burst = pacer.pollTransmitBurst(nowUptime: 100.0)
        expect(burst.count == 2 && burst[0].priority == .retransmit && burst[1].priority == .keyframe,
               "pacer transmits retransmit first, then keyframe")

        // 5. Monotonic Jitter Buffer reference-chain continuity & keyframe recovery
        var jitter = UDPJitterBuffer()
        let f1 = completedFrame!
        var f2 = f1; f2.frameId = 2; f2.isKeyframe = false; f2.firstArrivalMonoNs = 10_000_000
        var f3 = f1; f3.frameId = 3; f3.isKeyframe = false; f3.firstArrivalMonoNs = 16_000_000

        let res1 = jitter.insert(f1, nowMonoNs: 1_000_000)
        expect(res1.deliverable.map(\.frameId) == [1] && !res1.needsKeyframe,
               "initial keyframe 1 delivers immediately")
        // Arrive f3 out-of-order before f2
        let res3 = jitter.insert(f3, nowMonoNs: 16_000_000)
        expect(res3.deliverable.isEmpty, "out-of-order P-frame 3 waits for frame 2")
        // Arrive f2 in time -> both f2 and f3 deliver in order!
        let res2 = jitter.insert(f2, nowMonoNs: 18_000_000)
        expect(res2.deliverable.map(\.frameId) == [2, 3],
               "arrival of missing frame 2 releases [2, 3] in sequence order")

        // Expire an out-of-order frame past 45ms -> reference chain breaks and requests keyframe
        var f5 = f1; f5.frameId = 5; f5.isKeyframe = false; f5.firstArrivalMonoNs = 20_000_000
        _ = jitter.insert(f5, nowMonoNs: 20_000_000)
        let expiredPoll = jitter.pollDeliverable(nowMonoNs: 70_000_000)
        expect(expiredPoll.deliverable.isEmpty && expiredPoll.needsKeyframe && jitter.referenceChainBroken,
               "expiring buffered frame past 45ms breaks reference chain and requests keyframe")

        print("UDPMediaEngineSelfTest PASS")
    }
}

import Foundation

private func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() { fatalError(message) }
}

@main
struct UDPMediaFECSelfTest {
    static func main() {
        // 1. GF(256) field identities
        for a in 1...255 {
            let invA = UDPMediaGF256.inv(UInt8(a))
            expect(UDPMediaGF256.mul(UInt8(a), invA) == 1, "a * inv(a) must equal 1 in GF(256)")
        }

        // 2. Bitrate budget deduction invariant: encoderBitrate + fecOverhead <= totalBudget
        let budget = 40_000_000
        let encBitrate = UDPMediaFECBitratePolicy.encoderBitrate(
            totalBudgetBps: budget,
            lossFraction: 0.03,
            bounds: 8_000_000...100_000_000
        )
        expect(encBitrate == 34_000_000, "15% FEC overhead at 3% loss deducts 6 Mbps from 40 Mbps budget")

        // 3. Single-loss XOR parity recovery and multi-loss Cauchy RS recovery (including shorter final shard)
        var dataShards: [Data] = []
        for idx in 0..<10 {
            let len = (idx == 9) ? 437 : 1200 // final shard is shorter (437 bytes)
            let bytes = (0..<len).map { UInt8((idx * 31 + $0 * 17) & 0xFF) }
            dataShards.append(Data(bytes))
        }
        let parityShards = UDPMediaFECEncoder.encodeParityShards(
            dataShards: dataShards,
            lossFraction: 0.06,
            isKeyframe: true
        )
        expect(parityShards.count == 2, "10 data shards at 20% FEC produces 2 parity shards")

        // Descriptor round-trip
        for shard in parityShards {
            let decodedDesc = UDPMediaParityDescriptor(
                fragIndex: shard.descriptor.encodedFragIndex,
                fragCount: shard.descriptor.encodedFragCount
            )
            expect(decodedDesc == shard.descriptor, "Parity descriptor packs into 32-bit fragIndex/fragCount losslessly")
        }

        // Lose shard 2 (1200B) and shard 9 (final shard, 437B) — recover both using the 2 parity shards!
        var presentData: [Int: Data] = [:]
        for (i, shard) in dataShards.enumerated() where i != 2 && i != 9 {
            presentData[i] = shard
        }
        var presentParity: [Int: Data] = [:]
        for shard in parityShards {
            presentParity[shard.descriptor.parityIndexInBlock] = shard.payload
        }
        let recovered = UDPMediaFECEncoder.recoverBlockDataShards(
            blockDataCount: 10,
            lastDataShardLength: 437,
            shardStrideLength: 1200,
            presentDataShards: presentData,
            presentParityShards: presentParity
        )
        expect(recovered?[2] == dataShards[2], "Cauchy RS recovers middle 1200B shard")
        expect(recovered?[9] == dataShards[9] && recovered?[9]?.count == 437,
               "Cauchy RS recovers final variable-length 437B shard without padding")

        // 4. U5 safety: addScaled clamps to min(destination.count, source.count) and recoverBlockDataShards rejects short/malformed parity
        var shortDest: [UInt8] = [0x11, 0x22, 0x33]
        let longerSource = Data([0x01, 0x02, 0x03, 0x04, 0x05, 0x06])
        UDPMediaGF256.addScaled(destination: &shortDest, source: longerSource, coeff: 1)
        expect(shortDest == [0x11 ^ 0x01, 0x22 ^ 0x02, 0x33 ^ 0x03],
               "UDPMediaGF256.addScaled clamps safely when source is longer than destination")

        let truncatedParity: [Int: Data] = [
            0: parityShards[0].payload.prefix(120), // shorter than 1200B stride!
            1: parityShards[1].payload.prefix(120),
        ]
        let rejectedShortParity = UDPMediaFECEncoder.recoverBlockDataShards(
            blockDataCount: 10,
            lastDataShardLength: 437,
            shardStrideLength: 1200,
            presentDataShards: presentData,
            presentParityShards: truncatedParity
        )
        expect(rejectedShortParity == nil,
               "recoverBlockDataShards must safely reject truncated .videoParity shards without out-of-bounds crash")

        var corruptedFinalLenData = presentData
        corruptedFinalLenData[9] = Data(repeating: 0xAA, count: 300) // != lastDataShardLength 437
        var singleLossData = corruptedFinalLenData
        singleLossData.removeValue(forKey: 1)
        let rejectedBadFinalLen = UDPMediaFECEncoder.recoverBlockDataShards(
            blockDataCount: 10,
            lastDataShardLength: 437,
            shardStrideLength: 1200,
            presentDataShards: singleLossData,
            presentParityShards: [0: parityShards[0].payload]
        )
        expect(rejectedBadFinalLen == nil,
               "recoverBlockDataShards must reject mismatched final data shard length")

        print("UDPMediaFECSelfTest PASS")
    }
}

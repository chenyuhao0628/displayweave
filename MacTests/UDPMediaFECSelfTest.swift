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

        print("UDPMediaFECSelfTest PASS")
    }
}

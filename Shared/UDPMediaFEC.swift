import Foundation

/// Galois Field GF(2^8) with primitive polynomial x^8 + x^4 + x^3 + x^2 + 1 (0x11d)
/// and Cauchy / XOR Reed-Solomon frame-level FEC for `udpMediaV1`.
enum UDPMediaGF256 {
    static let tables: (exp: [UInt8], log: [UInt8]) = {
        var exp = [UInt8](repeating: 0, count: 512)
        var log = [UInt8](repeating: 0, count: 256)
        var x: Int = 1
        for i in 0..<255 {
            exp[i] = UInt8(x)
            exp[i + 255] = UInt8(x)
            log[x] = UInt8(i)
            x <<= 1
            if (x & 0x100) != 0 {
                x ^= 0x11d
            }
        }
        exp[510] = exp[0]
        exp[511] = exp[1]
        return (exp, log)
    }()

    @inline(__always)
    static func mul(_ a: UInt8, _ b: UInt8) -> UInt8 {
        if a == 0 || b == 0 { return 0 }
        let logA = Int(tables.log[Int(a)])
        let logB = Int(tables.log[Int(b)])
        return tables.exp[logA + logB]
    }

    @inline(__always)
    static func inv(_ a: UInt8) -> UInt8 {
        precondition(a != 0, "GF(256) division by zero")
        let logA = Int(tables.log[Int(a)])
        return tables.exp[255 - logA]
    }

    /// Cauchy coefficient for parity row `p` (0..<16) and data column `j` (0..<64).
    /// Row 0 uses all-1s (pure XOR parity) for fast single-loss recovery;
    /// rows 1..15 use Cauchy 1 / (p ^ (16 + j)) over GF(256).
    static func coefficient(parityRow p: Int, dataCol j: Int) -> UInt8 {
        if p == 0 { return 1 }
        return inv(UInt8(p) ^ UInt8(16 + j))
    }

    static func addScaled(destination: inout [UInt8], source: Data, coeff: UInt8) {
        guard coeff != 0 else { return }
        if coeff == 1 {
            source.withUnsafeBytes { raw in
                guard let base = raw.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return }
                for i in 0..<source.count {
                    destination[i] ^= base[i]
                }
            }
        } else {
            let logCoeff = Int(tables.log[Int(coeff)])
            let exp = tables.exp
            let log = tables.log
            source.withUnsafeBytes { raw in
                guard let base = raw.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return }
                for i in 0..<source.count {
                    let b = base[i]
                    if b != 0 {
                        destination[i] ^= exp[logCoeff + Int(log[Int(b)])]
                    }
                }
            }
        }
    }
}

/// Bitrate budget allocation policy that deducts FEC parity overhead from the
/// target network budget before setting the VideoToolbox encoder bitrate.
enum UDPMediaFECBitratePolicy {
    static let maxBlocksPerFrame = 16
    static let maxDataShardsPerBlock = 64
    static let maxParityShardsPerBlock = 15

    static func overheadFraction(lossFraction: Double, isKeyframe: Bool = false) -> Double {
        let sanitizedLoss = lossFraction.isFinite ? max(0.0, min(1.0, lossFraction)) : 0.0
        let base: Double
        if sanitizedLoss >= 0.05 {
            base = 0.20
        } else if sanitizedLoss >= 0.01 {
            base = 0.15
        } else {
            base = 0.05
        }
        return isKeyframe ? max(base, 0.12) : base
    }

    static func parityShardCount(dataShardCount: Int, lossFraction: Double, isKeyframe: Bool) -> Int {
        guard dataShardCount > 0 else { return 0 }
        let ratio = overheadFraction(lossFraction: lossFraction, isKeyframe: isKeyframe)
        let raw = Int((Double(dataShardCount) * ratio).rounded(.up))
        let minimum = (isKeyframe || lossFraction >= 0.005) ? 1 : 0
        return min(maxParityShardsPerBlock, max(minimum, raw))
    }

    /// Deducts active FEC overhead from `totalBudgetBps` so `encoderBitrate + fecBitrate <= totalBudgetBps`.
    static func encoderBitrate(
        totalBudgetBps: Int,
        lossFraction: Double,
        bounds: ClosedRange<Int>
    ) -> Int {
        let overhead = overheadFraction(lossFraction: lossFraction, isKeyframe: false)
        let deducted = Int((Double(totalBudgetBps) * (1.0 - overhead)).rounded())
        return min(max(deducted, bounds.lowerBound), bounds.upperBound)
    }
}

/// Metadata packed into `(fragIndex, fragCount)` of a `.videoParity` packet header.
struct UDPMediaParityDescriptor: Equatable, Sendable {
    var blockIndex: Int          // 0..<16
    var blockDataCount: Int      // 1...64
    var parityIndexInBlock: Int  // 0..<15
    var blockParityCount: Int    // 1...15
    var lastDataShardLength: Int // 1...4095

    var encodedFragIndex: UInt16 {
        UInt16(((blockIndex & 0x0F) << 12) | ((blockDataCount & 0xFF) << 4) | (parityIndexInBlock & 0x0F))
    }

    var encodedFragCount: UInt16 {
        UInt16(((lastDataShardLength & 0x0FFF) << 4) | (blockParityCount & 0x0F))
    }

    init(
        blockIndex: Int,
        blockDataCount: Int,
        parityIndexInBlock: Int,
        blockParityCount: Int,
        lastDataShardLength: Int
    ) {
        self.blockIndex = blockIndex
        self.blockDataCount = blockDataCount
        self.parityIndexInBlock = parityIndexInBlock
        self.blockParityCount = blockParityCount
        self.lastDataShardLength = lastDataShardLength
    }

    init?(fragIndex: UInt16, fragCount: UInt16) {
        let blockIdx = Int((fragIndex >> 12) & 0x0F)
        let dataCount = Int((fragIndex >> 4) & 0xFF)
        let parityIdx = Int(fragIndex & 0x0F)
        let lastLen = Int((fragCount >> 4) & 0x0FFF)
        let parityCount = Int(fragCount & 0x0F)
        guard dataCount >= 1,
              dataCount <= UDPMediaFECBitratePolicy.maxDataShardsPerBlock,
              parityCount >= 1,
              parityCount <= UDPMediaFECBitratePolicy.maxParityShardsPerBlock,
              parityIdx < parityCount,
              lastLen >= 1,
              lastLen <= UDPMediaHeader.maxPayloadLength else {
            return nil
        }
        self.blockIndex = blockIdx
        self.blockDataCount = dataCount
        self.parityIndexInBlock = parityIdx
        self.blockParityCount = parityCount
        self.lastDataShardLength = lastLen
    }
}

struct UDPMediaParityShard: Equatable, Sendable {
    let descriptor: UDPMediaParityDescriptor
    let payload: Data
}

enum UDPMediaFECEncoder {
    /// Generates parity shards across blocks of up to 64 data shards.
    static func encodeParityShards(
        dataShards: [Data],
        lossFraction: Double,
        isKeyframe: Bool
    ) -> [UDPMediaParityShard] {
        guard !dataShards.isEmpty else { return [] }
        let strideSize = UDPMediaFECBitratePolicy.maxDataShardsPerBlock
        let maxTotalShards = strideSize * UDPMediaFECBitratePolicy.maxBlocksPerFrame
        guard dataShards.count <= maxTotalShards else { return [] }

        var output: [UDPMediaParityShard] = []
        var blockIndex = 0
        var offset = 0
        while offset < dataShards.count && blockIndex < UDPMediaFECBitratePolicy.maxBlocksPerFrame {
            let end = min(offset + strideSize, dataShards.count)
            let blockShards = Array(dataShards[offset..<end])
            let parityCount = UDPMediaFECBitratePolicy.parityShardCount(
                dataShardCount: blockShards.count,
                lossFraction: lossFraction,
                isKeyframe: isKeyframe
            )
            if parityCount > 0 {
                let shardLength = blockShards.map(\.count).max() ?? 0
                let lastLen = blockShards.last?.count ?? shardLength
                if shardLength > 0 && lastLen > 0 {
                    for p in 0..<parityCount {
                        var parityBytes = [UInt8](repeating: 0, count: shardLength)
                        for (j, shard) in blockShards.enumerated() {
                            let coeff = UDPMediaGF256.coefficient(parityRow: p, dataCol: j)
                            UDPMediaGF256.addScaled(destination: &parityBytes, source: shard, coeff: coeff)
                        }
                        let descriptor = UDPMediaParityDescriptor(
                            blockIndex: blockIndex,
                            blockDataCount: blockShards.count,
                            parityIndexInBlock: p,
                            blockParityCount: parityCount,
                            lastDataShardLength: lastLen
                        )
                        output.append(UDPMediaParityShard(descriptor: descriptor, payload: Data(parityBytes)))
                    }
                }
            }
            offset = end
            blockIndex += 1
        }
        return output
    }

    /// Recovers missing data shards for a single block when
    /// `presentDataCount + presentParityCount >= blockDataCount`.
    static func recoverBlockDataShards(
        blockDataCount: Int,
        lastDataShardLength: Int,
        shardStrideLength: Int,
        presentDataShards: [Int: Data],
        presentParityShards: [Int: Data]
    ) -> [Int: Data]? {
        var missingCols: [Int] = []
        for col in 0..<blockDataCount {
            if presentDataShards[col] == nil {
                missingCols.append(col)
            }
        }
        if missingCols.isEmpty { return [:] }
        let m = missingCols.count
        guard presentParityShards.count >= m else { return nil }

        let sortedParityRows = presentParityShards.keys.sorted().prefix(m)
        var matrix = [[UInt8]](repeating: [UInt8](repeating: 0, count: m), count: m)
        var rhs = [[UInt8]](repeating: [UInt8](repeating: 0, count: shardStrideLength), count: m)

        for (eqIdx, pRow) in sortedParityRows.enumerated() {
            guard let parityData = presentParityShards[pRow],
                  parityData.count == shardStrideLength else { return nil }
            rhs[eqIdx] = [UInt8](parityData)
            // Subtract (XOR) contributions from all known data shards in this block
            for col in 0..<blockDataCount {
                if let knownData = presentDataShards[col] {
                    let coeff = UDPMediaGF256.coefficient(parityRow: pRow, dataCol: col)
                    UDPMediaGF256.addScaled(destination: &rhs[eqIdx], source: knownData, coeff: coeff)
                }
            }
            for (varIdx, missingCol) in missingCols.enumerated() {
                matrix[eqIdx][varIdx] = UDPMediaGF256.coefficient(parityRow: pRow, dataCol: missingCol)
            }
        }

        // Gaussian elimination over GF(256)
        for pivot in 0..<m {
            var swapRow = pivot
            while swapRow < m && matrix[swapRow][pivot] == 0 {
                swapRow += 1
            }
            guard swapRow < m else { return nil }
            if swapRow != pivot {
                matrix.swapAt(pivot, swapRow)
                rhs.swapAt(pivot, swapRow)
            }
            let pivotVal = matrix[pivot][pivot]
            if pivotVal != 1 {
                let invPivot = UDPMediaGF256.inv(pivotVal)
                for col in pivot..<m {
                    matrix[pivot][col] = UDPMediaGF256.mul(matrix[pivot][col], invPivot)
                }
                for b in 0..<shardStrideLength {
                    rhs[pivot][b] = UDPMediaGF256.mul(rhs[pivot][b], invPivot)
                }
            }
            for row in 0..<m where row != pivot {
                let factor = matrix[row][pivot]
                guard factor != 0 else { continue }
                for col in pivot..<m {
                    matrix[row][col] ^= UDPMediaGF256.mul(factor, matrix[pivot][col])
                }
                let pivotRhs = Data(rhs[pivot])
                UDPMediaGF256.addScaled(destination: &rhs[row], source: pivotRhs, coeff: factor)
            }
        }

        var recovered: [Int: Data] = [:]
        for (varIdx, missingCol) in missingCols.enumerated() {
            let targetLength = (missingCol == blockDataCount - 1) ? lastDataShardLength : shardStrideLength
            guard targetLength >= 1, targetLength <= shardStrideLength else { return nil }
            recovered[missingCol] = Data(rhs[varIdx].prefix(targetLength))
        }
        return recovered
    }
}

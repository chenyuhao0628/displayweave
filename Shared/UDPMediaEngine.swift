import Foundation

/// Reassembled video frame delivered by `UDPMediaReassembler` and `UDPJitterBuffer`.
struct UDPMediaFrameEnvelope: Equatable, Sendable {
    static let metadataPrefixLength = 16
    static let maxFrameBytes = 4 * 1024 * 1024

    var frameId: UInt32
    var isKeyframe: Bool
    var captureTimestampMs: Int64
    var sendTimestampUs: UInt32
    var configVersion: Int64
    var annexB: Data
    var firstArrivalMonoNs: UInt64
    var recoveredByFEC: Bool = false
}

enum UDPPacerPriority: Int, Comparable, Sendable {
    case retransmit = 0
    case keyframe = 1
    case normalVideo = 2
    case fecParity = 3

    static func < (lhs: UDPPacerPriority, rhs: UDPPacerPriority) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

struct UDPQueuedDatagram: Sendable, Equatable {
    let priority: UDPPacerPriority
    let frameId: UInt32
    let fragIndex: UInt16
    let isParity: Bool
    let datagram: Data
}

/// WebRTC-inspired debt-based packet pacer with priority ordering
/// (`retransmit > keyframe > normalVideo > fecParity`) and automatic stale
/// P-frame purge on new IDR arrival.
struct UDPDebtPacer: Sendable {
    static let maxSingleBurstBytes = 32 * 1024
    static let minBurstBytes = 1400
    static let maxDebtWindowSeconds: Double = 0.060
    static let maxQueuedPackets = 2048

    private(set) var pacingRateBps: Int
    private(set) var debtBytes: Double = 0
    private var lastTickUptime: TimeInterval?
    private(set) var queue: [UDPQueuedDatagram] = []
    private(set) var purgedStaleFragments = 0

    init(targetBitrateBps: Int) {
        self.pacingRateBps = Self.pacingRate(forTargetBitrateBps: targetBitrateBps)
    }

    static func pacingRate(forTargetBitrateBps targetBitrateBps: Int) -> Int {
        let clamped = max(1_000_000, min(targetBitrateBps, 250_000_000))
        return Int((Double(clamped) * 1.20).rounded())
    }

    mutating func updateTargetBitrate(_ targetBitrateBps: Int) {
        pacingRateBps = Self.pacingRate(forTargetBitrateBps: targetBitrateBps)
    }

    mutating func enqueueFrameDatagrams(_ items: [UDPQueuedDatagram], isKeyframe: Bool, frameId: UInt32) {
        if isKeyframe {
            let before = queue.count
            queue.removeAll { queued in
                queued.frameId < frameId
                    && (queued.priority == .normalVideo || queued.priority == .fecParity)
            }
            purgedStaleFragments += max(0, before - queue.count)
        }
        for item in items {
            if queue.count >= Self.maxQueuedPackets {
                if let fecIdx = queue.lastIndex(where: { $0.priority == .fecParity }) {
                    queue.remove(at: fecIdx)
                } else {
                    break
                }
            }
            insertOrdered(item)
        }
    }

    mutating func enqueueRetransmit(_ item: UDPQueuedDatagram) {
        guard queue.count < Self.maxQueuedPackets else { return }
        insertOrdered(item)
    }

    private mutating func insertOrdered(_ item: UDPQueuedDatagram) {
        if let idx = queue.firstIndex(where: { $0.priority > item.priority }) {
            queue.insert(item, at: idx)
        } else {
            queue.append(item)
        }
    }

    /// Drains debt according to elapsed monotonic time and returns a bounded burst
    /// of datagrams ready for immediate socket transmission.
    mutating func pollTransmitBurst(nowUptime: TimeInterval) -> [UDPQueuedDatagram] {
        let bytesPerSec = Double(pacingRateBps) / 8.0
        if let last = lastTickUptime, nowUptime.isFinite, nowUptime >= last {
            let dt = min(nowUptime - last, 0.250)
            debtBytes = max(0.0, debtBytes - bytesPerSec * dt)
        }
        lastTickUptime = nowUptime
        guard !queue.isEmpty else { return [] }

        let maxDebt = bytesPerSec * Self.maxDebtWindowSeconds
        guard debtBytes < maxDebt else { return [] }

        let fiveMsBurst = Int((bytesPerSec * 0.005).rounded())
        let burstBudget = min(Self.maxSingleBurstBytes, max(Self.minBurstBytes, fiveMsBurst))
        var sentBytes = 0
        var ready: [UDPQueuedDatagram] = []

        while let first = queue.first {
            let size = first.datagram.count
            if !ready.isEmpty && (sentBytes + size > burstBudget || debtBytes + Double(size) > maxDebt) {
                break
            }
            queue.removeFirst()
            ready.append(first)
            sentBytes += size
            debtBytes = min(maxDebt, debtBytes + Double(size))
            if sentBytes >= burstBudget {
                break
            }
        }
        return ready
    }

    var queuedPacketCount: Int { queue.count }
}

/// Bounded sender-side cache of recently transmitted data fragments for NACK retransmission.
struct UDPRetransmitCache: Sendable {
    static let maxCachedFrames = 8
    static let maxCachedPackets = 512
    static let maxCacheAgeSeconds: TimeInterval = 0.080
    static let maxRttForRetransmitUs: UInt32 = 60_000

    struct Entry: Sendable {
        let frameId: UInt32
        let fragIndex: UInt16
        let fragCount: UInt16
        let flags: UDPMediaFlags
        let payload: Data
        let storedAtUptime: TimeInterval
        var retransmitCount: Int
    }

    private var entries: [UInt64: Entry] = [:]
    private var frameOrder: [UInt32] = []

    private static func key(frameId: UInt32, fragIndex: UInt16) -> UInt64 {
        (UInt64(frameId) << 16) | UInt64(fragIndex)
    }

    mutating func store(
        frameId: UInt32,
        fragIndex: UInt16,
        fragCount: UInt16,
        flags: UDPMediaFlags,
        payload: Data,
        nowUptime: TimeInterval
    ) {
        evictExpired(nowUptime: nowUptime)
        if !frameOrder.contains(frameId) {
            frameOrder.append(frameId)
            while frameOrder.count > Self.maxCachedFrames {
                let oldestFrame = frameOrder.removeFirst()
                entries = entries.filter { $0.value.frameId != oldestFrame }
            }
        }
        if entries.count >= Self.maxCachedPackets, let oldestFrame = frameOrder.first {
            frameOrder.removeFirst()
            entries = entries.filter { $0.value.frameId != oldestFrame }
        }
        let k = Self.key(frameId: frameId, fragIndex: fragIndex)
        entries[k] = Entry(
            frameId: frameId,
            fragIndex: fragIndex,
            fragCount: fragCount,
            flags: flags,
            payload: payload,
            storedAtUptime: nowUptime,
            retransmitCount: 0
        )
    }

    mutating func consumeForRetransmit(
        nack: UDPMediaNackPayload,
        nowUptime: TimeInterval
    ) -> [Entry] {
        guard nack.rttEstimateUs <= Self.maxRttForRetransmitUs else { return [] }
        evictExpired(nowUptime: nowUptime)
        var result: [Entry] = []
        let missing = nack.missingFragmentIndices(maxFragCount: UDPMediaHeader.maxFragmentsPerFrame)
        for fragIdx in missing {
            let k = Self.key(frameId: nack.frameId, fragIndex: fragIdx)
            guard var entry = entries[k],
                  entry.retransmitCount == 0,
                  nowUptime - entry.storedAtUptime <= Self.maxCacheAgeSeconds else {
                continue
            }
            entry.retransmitCount += 1
            entries[k] = entry
            result.append(entry)
        }
        return result
    }

    private mutating func evictExpired(nowUptime: TimeInterval) {
        guard nowUptime.isFinite else { return }
        entries = entries.filter { nowUptime - $0.value.storedAtUptime <= Self.maxCacheAgeSeconds }
        frameOrder.removeAll { frameId in
            !entries.values.contains(where: { $0.frameId == frameId })
        }
    }
}

/// Sender-side helper that fragments a video frame, generates FEC parity shards,
/// seals every packet with AES-128-GCM, populates the retransmit cache, and
/// enqueues into the debt pacer.
enum UDPMediaFramePacketizer {
    static func makeDataFragments(
        annexB: Data,
        captureTimestampMs: Int64,
        configVersion: Int64,
        maxPayloadBytes: Int = UDPMediaHeader.maxPayloadLength
    ) throws -> [Data] {
        guard annexB.count > 0, annexB.count <= UDPMediaFrameEnvelope.maxFrameBytes else {
            throw UDPMediaError.packetTooLarge
        }
        let chunkLimit = max(256, min(maxPayloadBytes, UDPMediaHeader.maxPayloadLength))
        var envelope = Data(capacity: UDPMediaFrameEnvelope.metadataPrefixLength + annexB.count)
        UDPMediaHeader.appendUInt64(&envelope, UInt64(bitPattern: captureTimestampMs))
        UDPMediaHeader.appendUInt64(&envelope, UInt64(bitPattern: configVersion))
        envelope.append(annexB)

        let totalFragments = (envelope.count + chunkLimit - 1) / chunkLimit
        guard totalFragments >= 1,
              totalFragments <= Int(UDPMediaHeader.maxFragmentsPerFrame) else {
            throw UDPMediaError.invalidFragmentBounds
        }

        var shards: [Data] = []
        shards.reserveCapacity(totalFragments)
        var offset = envelope.startIndex
        while offset < envelope.endIndex {
            let end = min(offset + chunkLimit, envelope.endIndex)
            shards.append(envelope.subdata(in: offset..<end))
            offset = end
        }
        return shards
    }
}

/// Receiver-side bounded frame reassembler with:
/// - Early submission as soon as all data shards arrive (never waits for parity),
/// - Immediate Cauchy/XOR FEC recovery when `missingData <= availableParity`,
/// - Monotonic-clock NACK bitmap generation (`max(2ms, RTT/2)`),
/// - Bounded memory (`max 4` incomplete frames, `max 4 MiB` per frame).
struct UDPMediaReassembler: Sendable {
    static let maxConcurrentFrames = 4
    static let maxAssemblyAgeNs: UInt64 = 50_000_000 // 50 ms
    static let minNackDelayNs: UInt64 = 2_000_000    // 2 ms

    private struct PartialFrame: Sendable {
        let frameId: UInt32
        let fragCount: UInt16
        var isKeyframe: Bool
        var sendTimeUs: UInt32
        let firstArrivalMonoNs: UInt64
        var lastArrivalMonoNs: UInt64
        var totalDataBytes = 0
        var dataFragments: [Int: Data] = [:]
        var parityBlocks: [Int: (descriptor: UDPMediaParityDescriptor, shards: [Int: Data])] = [:]
        var nackedFragments: Set<Int> = []
        var highestObservedFragIndex: Int = -1
    }

    private var partialFrames: [UInt32: PartialFrame] = [:]
    private var completedFrameIds: [UInt32] = []
    private(set) var highestCompletedFrameId: UInt32?
    private(set) var fecRecoveredFrames = 0
    private(set) var expiredIncompleteFrames = 0
    private(set) var needsKeyframe = false

    mutating func consumeKeyframeRequestFlag() -> Bool {
        let value = needsKeyframe
        needsKeyframe = false
        return value
    }

    mutating func ingest(
        packet: AuthenticatedUDPPacket,
        nowMonoNs: UInt64
    ) -> UDPMediaFrameEnvelope? {
        evictExpired(nowMonoNs: nowMonoNs)
        let header = packet.header
        guard header.packetType == .videoData || header.packetType == .videoParity else {
            return nil
        }
        let frameId = header.frameId
        if completedFrameIds.contains(frameId) {
            return nil
        }
        if let highest = highestCompletedFrameId,
           Int64(frameId) < Int64(highest) - 16 {
            return nil
        }

        if partialFrames[frameId] == nil {
            if partialFrames.count >= Self.maxConcurrentFrames,
               let oldestKey = partialFrames.min(by: { $0.value.firstArrivalMonoNs < $1.value.firstArrivalMonoNs })?.key {
                partialFrames.removeValue(forKey: oldestKey)
                expiredIncompleteFrames += 1
                needsKeyframe = true
            }
            let initialFragCount: UInt16
            if header.packetType == .videoData {
                initialFragCount = header.fragCount
            } else if let desc = UDPMediaParityDescriptor(fragIndex: header.fragIndex, fragCount: header.fragCount),
                      desc.blockIndex == 0 {
                initialFragCount = UInt16(desc.blockDataCount)
            } else {
                return nil
            }
            guard initialFragCount >= 1, initialFragCount <= UDPMediaHeader.maxFragmentsPerFrame else {
                return nil
            }
            partialFrames[frameId] = PartialFrame(
                frameId: frameId,
                fragCount: initialFragCount,
                isKeyframe: header.flags.contains(.keyframe),
                sendTimeUs: header.sendTimeUs,
                firstArrivalMonoNs: nowMonoNs,
                lastArrivalMonoNs: nowMonoNs
            )
        }

        guard var partial = partialFrames[frameId] else { return nil }
        partial.lastArrivalMonoNs = nowMonoNs
        if header.flags.contains(.keyframe) {
            partial.isKeyframe = true
        }

        switch header.packetType {
        case .videoData:
            guard header.fragCount == partial.fragCount,
                  header.fragIndex < partial.fragCount else {
                partialFrames.removeValue(forKey: frameId)
                return nil
            }
            let idx = Int(header.fragIndex)
            if partial.dataFragments[idx] == nil {
                guard partial.totalDataBytes + packet.payload.count <= UDPMediaFrameEnvelope.maxFrameBytes + 64 else {
                    partialFrames.removeValue(forKey: frameId)
                    return nil
                }
                partial.dataFragments[idx] = packet.payload
                partial.totalDataBytes += packet.payload.count
                partial.highestObservedFragIndex = max(partial.highestObservedFragIndex, idx)
            }

        case .videoParity:
            guard let desc = UDPMediaParityDescriptor(
                fragIndex: header.fragIndex,
                fragCount: header.fragCount
            ) else {
                return nil
            }
            var entry = partial.parityBlocks[desc.blockIndex] ?? (descriptor: desc, shards: [:])
            entry.descriptor = desc
            entry.shards[desc.parityIndexInBlock] = packet.payload
            partial.parityBlocks[desc.blockIndex] = entry

        default:
            break
        }

        // 1. Fast path: all data fragments have arrived! Submit immediately without waiting for parity.
        if partial.dataFragments.count == Int(partial.fragCount) {
            partialFrames.removeValue(forKey: frameId)
            return finalizeFrame(partial, recoveredByFEC: false)
        }

        // 2. FEC Recovery check per block
        let recoveredAny = attemptFECRecovery(&partial)
        if partial.dataFragments.count == Int(partial.fragCount) {
            partialFrames.removeValue(forKey: frameId)
            if recoveredAny { fecRecoveredFrames += 1 }
            return finalizeFrame(partial, recoveredByFEC: recoveredAny)
        }

        partialFrames[frameId] = partial
        return nil
    }

    private func attemptFECRecovery(_ partial: inout PartialFrame) -> Bool {
        guard !partial.parityBlocks.isEmpty else { return false }
        let strideSize = UDPMediaFECBitratePolicy.maxDataShardsPerBlock
        var recoveredAny = false

        for (blockIdx, blockEntry) in partial.parityBlocks {
            let desc = blockEntry.descriptor
            let blockStart = blockIdx * strideSize
            let blockEnd = blockStart + desc.blockDataCount
            guard blockEnd <= Int(partial.fragCount) else { continue }

            var presentData: [Int: Data] = [:]
            var maxKnownShardLen = 0
            for localCol in 0..<desc.blockDataCount {
                if let d = partial.dataFragments[blockStart + localCol] {
                    presentData[localCol] = d
                    maxKnownShardLen = max(maxKnownShardLen, d.count)
                }
            }
            let missingCount = desc.blockDataCount - presentData.count
            guard missingCount > 0, blockEntry.shards.count >= missingCount else {
                continue
            }
            let parityShardLen = blockEntry.shards.values.first?.count ?? maxKnownShardLen
            guard parityShardLen > 0 else { continue }

            if let recovered = UDPMediaFECEncoder.recoverBlockDataShards(
                blockDataCount: desc.blockDataCount,
                lastDataShardLength: desc.lastDataShardLength,
                shardStrideLength: parityShardLen,
                presentDataShards: presentData,
                presentParityShards: blockEntry.shards
            ) {
                for (localCol, data) in recovered {
                    let globalIdx = blockStart + localCol
                    if partial.dataFragments[globalIdx] == nil {
                        partial.dataFragments[globalIdx] = data
                        partial.totalDataBytes += data.count
                        recoveredAny = true
                    }
                }
            }
        }
        return recoveredAny
    }

    private mutating func finalizeFrame(
        _ partial: PartialFrame,
        recoveredByFEC: Bool
    ) -> UDPMediaFrameEnvelope? {
        var combined = Data(capacity: partial.totalDataBytes)
        for i in 0..<Int(partial.fragCount) {
            guard let chunk = partial.dataFragments[i] else { return nil }
            combined.append(chunk)
        }
        guard combined.count > UDPMediaFrameEnvelope.metadataPrefixLength else {
            return nil
        }
        let captureMs = Int64(bitPattern: UDPMediaHeader.readUInt64(combined, offset: 0))
        let configVer = Int64(bitPattern: UDPMediaHeader.readUInt64(combined, offset: 8))
        let annexB = combined.subdata(
            in: (combined.startIndex + UDPMediaFrameEnvelope.metadataPrefixLength)..<combined.endIndex
        )
        guard annexB.count <= UDPMediaFrameEnvelope.maxFrameBytes else { return nil }

        completedFrameIds.append(partial.frameId)
        if completedFrameIds.count > 64 {
            completedFrameIds.removeFirst(completedFrameIds.count - 64)
        }
        if let currentHighest = highestCompletedFrameId {
            if partial.frameId > currentHighest {
                highestCompletedFrameId = partial.frameId
            }
        } else {
            highestCompletedFrameId = partial.frameId
        }

        return UDPMediaFrameEnvelope(
            frameId: partial.frameId,
            isKeyframe: partial.isKeyframe,
            captureTimestampMs: captureMs,
            sendTimestampUs: partial.sendTimeUs,
            configVersion: configVer,
            annexB: annexB,
            firstArrivalMonoNs: partial.firstArrivalMonoNs,
            recoveredByFEC: recoveredByFEC
        )
    }

    /// Generates NACK bitmaps for incomplete frames whose local monotonic wait
    /// has exceeded `max(2ms, RTT/2)`.
    mutating func pollNacks(nowMonoNs: UInt64, rttUs: UInt32) -> [UDPMediaNackPayload] {
        evictExpired(nowMonoNs: nowMonoNs)
        let nackWaitNs = max(Self.minNackDelayNs, UInt64(rttUs) * 500)
        var nacks: [UDPMediaNackPayload] = []

        for (frameId, var partial) in partialFrames {
            guard nowMonoNs >= partial.firstArrivalMonoNs,
                  nowMonoNs - partial.firstArrivalMonoNs >= nackWaitNs else {
                continue
            }
            let totalFrags = Int(partial.fragCount)
            var missingIndices: [Int] = []
            for idx in 0..<totalFrags {
                if partial.dataFragments[idx] == nil && !partial.nackedFragments.contains(idx) {
                    missingIndices.append(idx)
                }
            }
            guard !missingIndices.isEmpty else { continue }
            // If more than 25% of a large frame (> 8 fragments) is missing, request an IDR instead of NACK storm
            if missingIndices.count > 8 && missingIndices.count * 4 > totalFrags {
                needsKeyframe = true
                continue
            }
            let baseFrag = missingIndices[0]
            var bitmap: UInt64 = 0
            var count: UInt16 = 0
            for idx in missingIndices {
                let offset = idx - baseFrag
                guard offset >= 0 && offset < 64 else { break }
                bitmap |= (UInt64(1) << offset)
                count += 1
                partial.nackedFragments.insert(idx)
            }
            partialFrames[frameId] = partial
            if count > 0 {
                nacks.append(
                    UDPMediaNackPayload(
                        frameId: frameId,
                        baseFragIndex: UInt16(baseFrag),
                        missingCount: count,
                        missingBitmap: bitmap,
                        rttEstimateUs: rttUs
                    )
                )
            }
        }
        return nacks
    }

    private mutating func evictExpired(nowMonoNs: UInt64) {
        let expiredKeys = partialFrames.compactMap { (key, value) -> UInt32? in
            nowMonoNs >= value.firstArrivalMonoNs
                && (nowMonoNs - value.firstArrivalMonoNs) >= Self.maxAssemblyAgeNs
                ? key : nil
        }
        if !expiredKeys.isEmpty {
            for key in expiredKeys {
                partialFrames.removeValue(forKey: key)
                expiredIncompleteFrames += 1
            }
            needsKeyframe = true
        }
    }
}

/// Receiver-side monotonic jitter buffer that enforces reference-chain continuity,
/// holds out-of-order P-frames up to `maxHoldDurationNs` (`45ms`), and flushes
/// immediately when a keyframe arrives.
struct UDPJitterBuffer: Sendable {
    static let maxBufferedFrames = 3
    static let maxHoldDurationNs: UInt64 = 45_000_000 // 45 ms

    private var buffer: [UDPMediaFrameEnvelope] = []
    private(set) var lastDeliveredFrameId: UInt32?
    private(set) var referenceChainBroken = false
    private(set) var droppedFrames = 0

    mutating func reset() {
        buffer.removeAll()
        lastDeliveredFrameId = nil
        referenceChainBroken = false
    }

    mutating func insert(
        _ frame: UDPMediaFrameEnvelope,
        nowMonoNs: UInt64
    ) -> (deliverable: [UDPMediaFrameEnvelope], needsKeyframe: Bool) {
        if frame.isKeyframe {
            // Keyframe restores reference chain immediately and supersedes any older queued frames
            let droppedOlder = buffer.filter { $0.frameId < frame.frameId }.count
            droppedFrames += droppedOlder
            buffer.removeAll { $0.frameId <= frame.frameId }
            referenceChainBroken = false
            lastDeliveredFrameId = frame.frameId
            var ready = [frame]
            ready.append(contentsOf: drainConsecutive())
            return (ready, false)
        }

        if let last = lastDeliveredFrameId, frame.frameId <= last {
            return ([], false)
        }

        if !buffer.contains(where: { $0.frameId == frame.frameId }) {
            buffer.append(frame)
            buffer.sort { $0.frameId < $1.frameId }
            while buffer.count > Self.maxBufferedFrames {
                buffer.removeFirst()
                droppedFrames += 1
                referenceChainBroken = true
            }
        }

        return pollDeliverable(nowMonoNs: nowMonoNs)
    }

    mutating func pollDeliverable(
        nowMonoNs: UInt64
    ) -> (deliverable: [UDPMediaFrameEnvelope], needsKeyframe: Bool) {
        // Expire any buffered frames older than maxHoldDurationNs
        let beforeCount = buffer.count
        buffer.removeAll { frame in
            !frame.isKeyframe
                && nowMonoNs >= frame.firstArrivalMonoNs
                && (nowMonoNs - frame.firstArrivalMonoNs) >= Self.maxHoldDurationNs
        }
        if buffer.count < beforeCount {
            droppedFrames += (beforeCount - buffer.count)
            referenceChainBroken = true
        }

        if referenceChainBroken {
            if let keyIdx = buffer.firstIndex(where: \.isKeyframe) {
                let keyframe = buffer[keyIdx]
                droppedFrames += keyIdx
                buffer.removeFirst(keyIdx + 1)
                referenceChainBroken = false
                lastDeliveredFrameId = keyframe.frameId
                var ready = [keyframe]
                ready.append(contentsOf: drainConsecutive())
                return (ready, false)
            }
            return ([], true)
        }

        let ready = drainConsecutive()
        let gapStalled = !buffer.isEmpty && ready.isEmpty
        return (ready, gapStalled && referenceChainBroken)
    }

    private mutating func drainConsecutive() -> [UDPMediaFrameEnvelope] {
        var ready: [UDPMediaFrameEnvelope] = []
        while let first = buffer.first {
            if first.isKeyframe {
                buffer.removeFirst()
                lastDeliveredFrameId = first.frameId
                referenceChainBroken = false
                ready.append(first)
            } else if let last = lastDeliveredFrameId, first.frameId == last &+ 1 {
                buffer.removeFirst()
                lastDeliveredFrameId = first.frameId
                ready.append(first)
            } else {
                break
            }
        }
        return ready
    }

    var bufferedCount: Int { buffer.count }
}

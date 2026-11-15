import CoreAudio
import CoreMedia
import Foundation

/// Converts captured `CMSampleBuffer` system audio into bounded 5 ms (`240` stereo
/// frames = `960` bytes at `48 kHz`) signed 16-bit little-endian interleaved PCM
/// chunks suitable for `udpAudioV1` transport.
struct AudioCapturePacketizer: Sendable {
    static let targetSampleRate: Int = 48_000
    static let targetChannels: Int = 2
    static let framesPerChunk: Int = 240 // 5 ms @ 48 kHz
    static let bytesPerFrame: Int = targetChannels * MemoryLayout<Int16>.size // 4 bytes
    static let chunkByteCount: Int = framesPerChunk * bytesPerFrame // 960 bytes
    /// Maximum buffered stereo frames (100 ms @ 48 kHz) to keep allocations bounded.
    static let maxBufferedFrames: Int = 4_800
    static let maxBufferedBytes: Int = maxBufferedFrames * bytesPerFrame

    private(set) var pendingBytes = Data()
    private var resamplePhase: Double = 0
    private(set) var emittedChunks: UInt64 = 0

    init() {
        pendingBytes.reserveCapacity(Self.chunkByteCount * 4)
    }

    mutating func reset() {
        pendingBytes.removeAll(keepingCapacity: true)
        resamplePhase = 0
        emittedChunks = 0
    }

    /// Extracts PCM samples from a `ScreenCaptureKit` audio `CMSampleBuffer`,
    /// converts to 48 kHz stereo S16LE, and returns zero or more 960-byte chunks.
    mutating func ingest(_ sampleBuffer: CMSampleBuffer) -> [Data] {
        guard CMSampleBufferIsValid(sampleBuffer),
              CMSampleBufferDataIsReady(sampleBuffer) else { return [] }
        let frameCount = Int(CMSampleBufferGetNumSamples(sampleBuffer))
        guard frameCount > 0, frameCount <= 96_000,
              let formatDesc = CMSampleBufferGetFormatDescription(sampleBuffer),
              let asbdPtr = CMAudioFormatDescriptionGetStreamBasicDescription(formatDesc) else {
            return []
        }
        let asbd = asbdPtr.pointee
        guard asbd.mFormatID == kAudioFormatLinearPCM,
              asbd.mSampleRate.isFinite,
              asbd.mSampleRate >= 8_000,
              asbd.mSampleRate <= 192_000,
              asbd.mChannelsPerFrame >= 1,
              asbd.mChannelsPerFrame <= 16 else {
            return []
        }

        var sizeNeeded: Int = 0
        let sizeStatus = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer,
            bufferListSizeNeededOut: &sizeNeeded,
            bufferListOut: nil,
            bufferListSize: 0,
            blockBufferAllocator: kCFAllocatorDefault,
            blockBufferMemoryAllocator: kCFAllocatorDefault,
            flags: 0,
            blockBufferOut: nil
        )
        guard sizeStatus == noErr,
              sizeNeeded >= MemoryLayout<AudioBufferList>.size,
              sizeNeeded <= 16_384 else {
            return []
        }
        let rawBufferList = UnsafeMutableRawPointer.allocate(
            byteCount: sizeNeeded,
            alignment: MemoryLayout<AudioBufferList>.alignment
        )
        defer { rawBufferList.deallocate() }
        rawBufferList.initializeMemory(as: UInt8.self, repeating: 0, count: sizeNeeded)
        let audioBufferListPtr = rawBufferList.bindMemory(to: AudioBufferList.self, capacity: 1)

        var blockBuffer: CMBlockBuffer?
        let status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer,
            bufferListSizeNeededOut: &sizeNeeded,
            bufferListOut: audioBufferListPtr,
            bufferListSize: sizeNeeded,
            blockBufferAllocator: kCFAllocatorDefault,
            blockBufferMemoryAllocator: kCFAllocatorDefault,
            flags: 0,
            blockBufferOut: &blockBuffer
        )
        guard status == noErr else { return [] }

        let buffers = UnsafeMutableAudioBufferListPointer(audioBufferListPtr)
        guard !buffers.isEmpty else { return [] }

        let isFloat = (asbd.mFormatFlags & kAudioFormatFlagIsFloat) != 0
        let isSignedInt = (asbd.mFormatFlags & kAudioFormatFlagIsSignedInteger) != 0
        let isNonInterleaved = (asbd.mFormatFlags & kAudioFormatFlagIsNonInterleaved) != 0
        let isBigEndian = (asbd.mFormatFlags & kAudioFormatFlagIsBigEndian) != 0
        let channels = Int(asbd.mChannelsPerFrame)
        let bits = Int(asbd.mBitsPerChannel)

        var left = [Float](repeating: 0, count: frameCount)
        var right = [Float](repeating: 0, count: frameCount)

        if isNonInterleaved {
            guard let ch0 = buffers[0].mData else { return [] }
            let ch1 = buffers.count > 1 ? buffers[1].mData : ch0
            let avail0 = Self.availableSamples(in: buffers[0], bitsPerSample: bits, interleavedChannels: 1)
            let avail1 = buffers.count > 1
                ? Self.availableSamples(in: buffers[1], bitsPerSample: bits, interleavedChannels: 1)
                : avail0
            let count = min(frameCount, min(avail0, avail1))
            guard count > 0 else { return [] }
            if count < frameCount {
                left.removeSubrange(count..<frameCount)
                right.removeSubrange(count..<frameCount)
            }
            for i in 0..<count {
                left[i] = Self.readNormalizedSample(
                    base: ch0, index: i, bits: bits, isFloat: isFloat,
                    isSignedInt: isSignedInt, isBigEndian: isBigEndian
                )
                right[i] = Self.readNormalizedSample(
                    base: ch1 ?? ch0, index: i, bits: bits, isFloat: isFloat,
                    isSignedInt: isSignedInt, isBigEndian: isBigEndian
                )
            }
        } else {
            guard let base = buffers[0].mData else { return [] }
            let avail = Self.availableSamples(in: buffers[0], bitsPerSample: bits, interleavedChannels: channels)
            let count = min(frameCount, avail)
            guard count > 0 else { return [] }
            if count < frameCount {
                left.removeSubrange(count..<frameCount)
                right.removeSubrange(count..<frameCount)
            }
            for i in 0..<count {
                let lIndex = i * channels
                let rIndex = channels > 1 ? (i * channels + 1) : lIndex
                left[i] = Self.readNormalizedSample(
                    base: base, index: lIndex, bits: bits, isFloat: isFloat,
                    isSignedInt: isSignedInt, isBigEndian: isBigEndian
                )
                right[i] = Self.readNormalizedSample(
                    base: base, index: rIndex, bits: bits, isFloat: isFloat,
                    isSignedInt: isSignedInt, isBigEndian: isBigEndian
                )
            }
        }

        return ingestFloat32Planar(left: left, right: right, sampleRate: asbd.mSampleRate)
    }

    /// Converts normalized `[-1.0, 1.0]` planar stereo Float32 samples into 960-byte
    /// 48 kHz S16LE chunks.
    mutating func ingestFloat32Planar(
        left: [Float],
        right: [Float],
        sampleRate: Double = 48_000
    ) -> [Data] {
        let count = min(left.count, right.count)
        guard count > 0, sampleRate.isFinite, sampleRate >= 8_000, sampleRate <= 192_000 else {
            return []
        }

        if abs(sampleRate - Double(Self.targetSampleRate)) < 0.5 {
            var pcm = Data(capacity: count * Self.bytesPerFrame)
            for i in 0..<count {
                Self.appendInt16LE(&pcm, Self.quantize(left[i]))
                Self.appendInt16LE(&pcm, Self.quantize(right[i]))
            }
            return ingestInterleavedS16LE(pcm)
        }

        let step = sampleRate / Double(Self.targetSampleRate)
        var pos = resamplePhase
        var pcm = Data(capacity: Int(Double(count) / step + 2) * Self.bytesPerFrame)
        while Int(pos) < count {
            let idx0 = Int(pos)
            let idx1 = min(idx0 + 1, count - 1)
            let frac = Float(pos - Double(idx0))
            let l = left[idx0] + (left[idx1] - left[idx0]) * frac
            let r = right[idx0] + (right[idx1] - right[idx0]) * frac
            Self.appendInt16LE(&pcm, Self.quantize(l))
            Self.appendInt16LE(&pcm, Self.quantize(r))
            pos += step
        }
        resamplePhase = max(0, pos - Double(count))
        return ingestInterleavedS16LE(pcm)
    }

    /// Appends raw 48 kHz stereo S16LE bytes (4-byte frame aligned) and drains
    /// complete 960-byte (5 ms) chunks while bounding buffered bytes to <= 100 ms.
    mutating func ingestInterleavedS16LE(_ data: Data) -> [Data] {
        let alignedCount = data.count - (data.count % Self.bytesPerFrame)
        guard alignedCount > 0 else { return [] }
        pendingBytes.append(data.prefix(alignedCount))

        if pendingBytes.count > Self.maxBufferedBytes {
            let excess = pendingBytes.count - Self.maxBufferedBytes
            let alignedExcess = excess + ((Self.bytesPerFrame - (excess % Self.bytesPerFrame)) % Self.bytesPerFrame)
            pendingBytes.removeFirst(min(alignedExcess, pendingBytes.count))
        }

        var chunks: [Data] = []
        let chunkCount = pendingBytes.count / Self.chunkByteCount
        guard chunkCount > 0 else { return [] }
        chunks.reserveCapacity(chunkCount)

        var offset = pendingBytes.startIndex
        for _ in 0..<chunkCount {
            let next = offset + Self.chunkByteCount
            chunks.append(Data(pendingBytes[offset..<next]))
            offset = next
            emittedChunks &+= 1
        }
        pendingBytes.removeFirst(chunkCount * Self.chunkByteCount)
        return chunks
    }

    private static func availableSamples(
        in buffer: AudioBuffer,
        bitsPerSample: Int,
        interleavedChannels: Int
    ) -> Int {
        let bytesPerSample = max(bitsPerSample / 8, 1)
        let frameStride = max(bytesPerSample * max(interleavedChannels, 1), 1)
        return Int(buffer.mDataByteSize) / frameStride
    }

    private static func readNormalizedSample(
        base: UnsafeMutableRawPointer,
        index: Int,
        bits: Int,
        isFloat: Bool,
        isSignedInt: Bool,
        isBigEndian: Bool
    ) -> Float {
        if isFloat && bits == 32 {
            var raw = base.loadUnaligned(fromByteOffset: index * 4, as: UInt32.self)
            if isBigEndian { raw = UInt32(bigEndian: raw) }
            let value = Float(bitPattern: raw)
            return value.isFinite ? min(max(value, -1.0), 1.0) : 0
        }
        if isSignedInt && bits == 16 {
            var raw = base.loadUnaligned(fromByteOffset: index * 2, as: Int16.self)
            if isBigEndian { raw = Int16(bigEndian: raw) }
            return Float(raw) / 32768.0
        }
        if isSignedInt && bits == 32 {
            var raw = base.loadUnaligned(fromByteOffset: index * 4, as: Int32.self)
            if isBigEndian { raw = Int32(bigEndian: raw) }
            return Float(Double(raw) / 2_147_483_648.0)
        }
        return 0
    }

    private static func quantize(_ sample: Float) -> Int16 {
        guard sample.isFinite else { return 0 }
        let clamped = min(max(sample, -1.0), 1.0)
        let scaled = (clamped * 32767.0).rounded()
        return Int16(clamping: Int32(scaled))
    }

    private static func appendInt16LE(_ data: inout Data, _ value: Int16) {
        let u = UInt16(bitPattern: value).littleEndian
        withUnsafeBytes(of: u) { data.append(contentsOf: $0) }
    }
}

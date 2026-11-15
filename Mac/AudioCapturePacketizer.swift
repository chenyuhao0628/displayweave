import AudioToolbox
import CoreAudio
import CoreMedia
import Foundation

/// Converts captured `CMSampleBuffer` system audio into bounded chunks for
/// `udpAudioV1` and `tcpAudioV1` transport:
/// - `formatOpus` (`1`): 20 ms (`960` stereo frames @ `48 kHz`, ~128 kbps) compressed Opus packets (`<= 1152` bytes) when negotiated via `"audioOpusV1"`, with automatic fallback to PCM.
/// - `formatPCM16LE` (`0`): 5 ms (`240` stereo frames = `960` bytes @ `48 kHz`) signed 16-bit little-endian interleaved PCM chunks.
struct AudioCapturePacketizer: Sendable {
    struct EncodedChunk: Equatable, Sendable {
        var formatFlags: UInt8
        var data: Data
        var frameCount: Int
    }

    static let formatPCM16LE: UInt8 = 0
    static let formatOpus: UInt8 = 1

    static let targetSampleRate: Int = 48_000
    static let targetChannels: Int = 2
    static let framesPerChunk: Int = 240 // 5 ms @ 48 kHz (PCM)
    static let opusFramesPerPacket: Int = 960 // 20 ms @ 48 kHz (Opus)
    static let opusTargetBitrate: UInt32 = 128_000
    static let maxEncodedPacketBytes: Int = 1_152
    static let bytesPerFrame: Int = targetChannels * MemoryLayout<Int16>.size // 4 bytes
    static let chunkByteCount: Int = framesPerChunk * bytesPerFrame // 960 bytes
    static let opusPacketPCMByteCount: Int = opusFramesPerPacket * bytesPerFrame // 3,840 bytes
    /// Maximum buffered stereo frames (100 ms @ 48 kHz) to keep allocations bounded.
    static let maxBufferedFrames: Int = 4_800
    static let maxBufferedBytes: Int = maxBufferedFrames * bytesPerFrame

    private(set) var pendingBytes = Data()
    private var resamplePhase: Double = 0
    private(set) var emittedChunks: UInt64 = 0
    private(set) var opusRequested: Bool = false
    private(set) var opusFallbackToPCM: Bool = false
    private var opusEncoder: OpusAudioEncoderBox?

    init(opusEnabled: Bool = false) {
        pendingBytes.reserveCapacity(Self.opusPacketPCMByteCount * 2)
        self.opusRequested = opusEnabled
    }

    var isUsingOpus: Bool {
        opusRequested && !opusFallbackToPCM
    }

    mutating func setOpusEnabled(_ enabled: Bool) {
        if opusRequested != enabled {
            opusRequested = enabled
            opusFallbackToPCM = false
            if !enabled {
                opusEncoder?.dispose()
                opusEncoder = nil
            }
        }
    }

    mutating func reset() {
        pendingBytes.removeAll(keepingCapacity: true)
        resamplePhase = 0
        emittedChunks = 0
        opusFallbackToPCM = false
        opusEncoder?.dispose()
        opusEncoder = nil
    }

    /// Extracts audio from a `ScreenCaptureKit` `CMSampleBuffer` and encodes into
    /// either 20 ms Opus packets (`formatOpus = 1`) when enabled or 5 ms S16LE PCM
    /// chunks (`formatPCM16LE = 0`) on fallback / legacy peers.
    mutating func ingestEncoded(_ sampleBuffer: CMSampleBuffer) -> [EncodedChunk] {
        guard let planar = extractPlanarFloat32(from: sampleBuffer) else {
            return []
        }
        return ingestFloat32PlanarEncoded(
            left: planar.left,
            right: planar.right,
            sampleRate: planar.sampleRate
        )
    }

    /// Extracts PCM samples from a `ScreenCaptureKit` audio `CMSampleBuffer`,
    /// converts to 48 kHz stereo S16LE, and returns zero or more 960-byte chunks.
    mutating func ingest(_ sampleBuffer: CMSampleBuffer) -> [Data] {
        guard let planar = extractPlanarFloat32(from: sampleBuffer) else {
            return []
        }
        return ingestFloat32Planar(
            left: planar.left,
            right: planar.right,
            sampleRate: planar.sampleRate
        )
    }

    private func extractPlanarFloat32(
        from sampleBuffer: CMSampleBuffer
    ) -> (left: [Float], right: [Float], sampleRate: Double)? {
        guard CMSampleBufferIsValid(sampleBuffer),
              CMSampleBufferDataIsReady(sampleBuffer) else { return nil }
        let frameCount = Int(CMSampleBufferGetNumSamples(sampleBuffer))
        guard frameCount > 0, frameCount <= 96_000,
              let formatDesc = CMSampleBufferGetFormatDescription(sampleBuffer),
              let asbdPtr = CMAudioFormatDescriptionGetStreamBasicDescription(formatDesc) else {
            return nil
        }
        let asbd = asbdPtr.pointee
        guard asbd.mFormatID == kAudioFormatLinearPCM,
              asbd.mSampleRate.isFinite,
              asbd.mSampleRate >= 8_000,
              asbd.mSampleRate <= 192_000,
              asbd.mChannelsPerFrame >= 1,
              asbd.mChannelsPerFrame <= 16 else {
            return nil
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
            return nil
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
        guard status == noErr else { return nil }

        let buffers = UnsafeMutableAudioBufferListPointer(audioBufferListPtr)
        guard !buffers.isEmpty else { return nil }

        let isFloat = (asbd.mFormatFlags & kAudioFormatFlagIsFloat) != 0
        let isSignedInt = (asbd.mFormatFlags & kAudioFormatFlagIsSignedInteger) != 0
        let isNonInterleaved = (asbd.mFormatFlags & kAudioFormatFlagIsNonInterleaved) != 0
        let isBigEndian = (asbd.mFormatFlags & kAudioFormatFlagIsBigEndian) != 0
        let channels = Int(asbd.mChannelsPerFrame)
        let bits = Int(asbd.mBitsPerChannel)

        var left = [Float](repeating: 0, count: frameCount)
        var right = [Float](repeating: 0, count: frameCount)

        if isNonInterleaved {
            guard let ch0 = buffers[0].mData else { return nil }
            let ch1 = buffers.count > 1 ? buffers[1].mData : ch0
            let avail0 = Self.availableSamples(in: buffers[0], bitsPerSample: bits, interleavedChannels: 1)
            let avail1 = buffers.count > 1
                ? Self.availableSamples(in: buffers[1], bitsPerSample: bits, interleavedChannels: 1)
                : avail0
            let count = min(frameCount, min(avail0, avail1))
            guard count > 0 else { return nil }
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
            guard let base = buffers[0].mData else { return nil }
            let avail = Self.availableSamples(in: buffers[0], bitsPerSample: bits, interleavedChannels: channels)
            let count = min(frameCount, avail)
            guard count > 0 else { return nil }
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

        return (left, right, asbd.mSampleRate)
    }

    /// Converts normalized `[-1.0, 1.0]` planar stereo Float32 samples into 960-byte
    /// 48 kHz S16LE chunks.
    mutating func ingestFloat32Planar(
        left: [Float],
        right: [Float],
        sampleRate: Double = 48_000
    ) -> [Data] {
        guard let pcm = resampleToS16LE(left: left, right: right, sampleRate: sampleRate) else {
            return []
        }
        return ingestInterleavedS16LE(pcm)
    }

    /// Converts normalized `[-1.0, 1.0]` planar stereo Float32 samples into either
    /// 20 ms Opus packets or 5 ms S16LE PCM chunks.
    mutating func ingestFloat32PlanarEncoded(
        left: [Float],
        right: [Float],
        sampleRate: Double = 48_000
    ) -> [EncodedChunk] {
        guard let pcm = resampleToS16LE(left: left, right: right, sampleRate: sampleRate) else {
            return []
        }
        return ingestInterleavedS16LEEncoded(pcm)
    }

    private mutating func resampleToS16LE(
        left: [Float],
        right: [Float],
        sampleRate: Double
    ) -> Data? {
        let count = min(left.count, right.count)
        guard count > 0, sampleRate.isFinite, sampleRate >= 8_000, sampleRate <= 192_000 else {
            return nil
        }

        if abs(sampleRate - Double(Self.targetSampleRate)) < 0.5 {
            var pcm = Data(capacity: count * Self.bytesPerFrame)
            for i in 0..<count {
                Self.appendInt16LE(&pcm, Self.quantize(left[i]))
                Self.appendInt16LE(&pcm, Self.quantize(right[i]))
            }
            return pcm
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
        return pcm
    }

    /// Appends raw 48 kHz stereo S16LE bytes (4-byte frame aligned) and drains
    /// complete 960-byte (5 ms) chunks while bounding buffered bytes to <= 100 ms.
    mutating func ingestInterleavedS16LE(_ data: Data) -> [Data] {
        appendBoundedS16LE(data)
        return drainPCMChunks()
    }

    /// Appends raw 48 kHz stereo S16LE bytes and drains either 20 ms Opus packets
    /// (`formatOpus = 1`) or 5 ms S16LE PCM chunks (`formatPCM16LE = 0`) with automatic fallback.
    mutating func ingestInterleavedS16LEEncoded(_ data: Data) -> [EncodedChunk] {
        appendBoundedS16LE(data)
        if isUsingOpus {
            if opusEncoder == nil {
                opusEncoder = OpusAudioEncoderBox(
                    sampleRate: Double(Self.targetSampleRate),
                    channels: UInt32(Self.targetChannels),
                    framesPerPacket: UInt32(Self.opusFramesPerPacket),
                    bitrate: Self.opusTargetBitrate
                )
                if opusEncoder == nil {
                    opusFallbackToPCM = true
                }
            }
            if let encoder = opusEncoder {
                var out: [EncodedChunk] = []
                while pendingBytes.count >= encoder.requiredInputBytesForNextPacket {
                    if let result = encoder.encodeOnePacket(from: pendingBytes) {
                        pendingBytes.removeFirst(min(result.consumedPCMBytes, pendingBytes.count))
                        emittedChunks &+= 1
                        out.append(EncodedChunk(
                            formatFlags: Self.formatOpus,
                            data: result.opusPacket,
                            frameCount: Self.opusFramesPerPacket
                        ))
                    } else {
                        opusEncoder?.dispose()
                        opusEncoder = nil
                        opusFallbackToPCM = true
                        break
                    }
                }
                if !opusFallbackToPCM {
                    return out
                }
            }
        }
        return drainPCMChunks().map {
            EncodedChunk(formatFlags: Self.formatPCM16LE, data: $0, frameCount: Self.framesPerChunk)
        }
    }

    private mutating func appendBoundedS16LE(_ data: Data) {
        let alignedCount = data.count - (data.count % Self.bytesPerFrame)
        guard alignedCount > 0 else { return }
        pendingBytes.append(data.prefix(alignedCount))

        if pendingBytes.count > Self.maxBufferedBytes {
            let excess = pendingBytes.count - Self.maxBufferedBytes
            let alignedExcess = excess + ((Self.bytesPerFrame - (excess % Self.bytesPerFrame)) % Self.bytesPerFrame)
            pendingBytes.removeFirst(min(alignedExcess, pendingBytes.count))
        }
    }

    private mutating func drainPCMChunks() -> [Data] {
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

/// Reference-counted wrapper owning an `AudioConverterRef` configured for `kAudioFormatOpus`
/// so copying/resetting `AudioCapturePacketizer` never leaks or double-frees converters.
final class OpusAudioEncoderBox: @unchecked Sendable {
    struct EncodeResult {
        var opusPacket: Data
        var consumedPCMBytes: Int
    }

    private static let needMoreInputStatus: OSStatus = -77_402

    private var converter: AudioConverterRef?
    private let channels: UInt32
    private let bytesPerFrame: Int
    private let framesPerPacket: Int
    private let leadingPrimeFrames: Int
    private var isPrimed: Bool = false
    private var outputScratch = [UInt8](repeating: 0, count: AudioCapturePacketizer.maxEncodedPacketBytes)

    private final class InputContext {
        var pcmBase: UnsafeRawPointer?
        var totalPCMBytes: Int = 0
        var consumedPCMBytes: Int = 0
        var bytesPerFrame: Int = 4
        var channels: UInt32 = 2
    }

    private let inputContext = InputContext()

    var requiredInputBytesForNextPacket: Int {
        let frames = isPrimed ? framesPerPacket : (framesPerPacket + leadingPrimeFrames)
        return frames * bytesPerFrame
    }

    init?(sampleRate: Double, channels: UInt32, framesPerPacket: UInt32, bitrate: UInt32) {
        let bpf = Int(channels) * MemoryLayout<Int16>.size
        var srcFormat = AudioStreamBasicDescription(
            mSampleRate: sampleRate,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kLinearPCMFormatFlagIsSignedInteger | kLinearPCMFormatFlagIsPacked,
            mBytesPerPacket: UInt32(bpf),
            mFramesPerPacket: 1,
            mBytesPerFrame: UInt32(bpf),
            mChannelsPerFrame: channels,
            mBitsPerChannel: 16,
            mReserved: 0
        )
        var dstFormat = AudioStreamBasicDescription(
            mSampleRate: sampleRate,
            mFormatID: kAudioFormatOpus,
            mFormatFlags: 0,
            mBytesPerPacket: 0,
            mFramesPerPacket: framesPerPacket,
            mBytesPerFrame: 0,
            mChannelsPerFrame: channels,
            mBitsPerChannel: 0,
            mReserved: 0
        )
        var created: AudioConverterRef?
        let status = AudioConverterNew(&srcFormat, &dstFormat, &created)
        guard status == noErr, let created else {
            return nil
        }

        var targetBitrate = bitrate
        _ = AudioConverterSetProperty(
            created,
            kAudioConverterEncodeBitRate,
            UInt32(MemoryLayout<UInt32>.size),
            &targetBitrate
        )

        var primeInfo = AudioConverterPrimeInfo(leadingFrames: 0, trailingFrames: 0)
        var primeSize = UInt32(MemoryLayout<AudioConverterPrimeInfo>.size)
        let primeStatus = AudioConverterGetProperty(
            created,
            kAudioConverterPrimeInfo,
            &primeSize,
            &primeInfo
        )
        let primeFrames = (primeStatus == noErr) ? min(max(Int(primeInfo.leadingFrames), 0), 1_920) : 312

        self.converter = created
        self.channels = channels
        self.bytesPerFrame = bpf
        self.framesPerPacket = Int(framesPerPacket)
        self.leadingPrimeFrames = primeFrames
    }

    deinit {
        dispose()
    }

    func dispose() {
        if let converter {
            AudioConverterDispose(converter)
            self.converter = nil
        }
        isPrimed = false
    }

    func encodeOnePacket(from pendingPCM: Data) -> EncodeResult? {
        guard let activeConverter = converter else { return nil }
        guard pendingPCM.count >= requiredInputBytesForNextPacket else { return nil }

        return pendingPCM.withUnsafeBytes { rawIn -> EncodeResult? in
            guard let inBase = rawIn.baseAddress else { return nil }
            inputContext.pcmBase = inBase
            inputContext.totalPCMBytes = pendingPCM.count
            inputContext.consumedPCMBytes = 0
            inputContext.bytesPerFrame = bytesPerFrame
            inputContext.channels = channels

            return outputScratch.withUnsafeMutableBytes { rawOut -> EncodeResult? in
                guard let outBase = rawOut.baseAddress else { return nil }
                var outBufferList = AudioBufferList(
                    mNumberBuffers: 1,
                    mBuffers: AudioBuffer(
                        mNumberChannels: channels,
                        mDataByteSize: UInt32(AudioCapturePacketizer.maxEncodedPacketBytes),
                        mData: outBase
                    )
                )
                var packetDesc = AudioStreamPacketDescription()
                var ioOutputDataPackets: UInt32 = 1

                let callback: AudioConverterComplexInputDataProc = { _, ioNumberDataPackets, ioData, outDataPacketDescription, userData in
                    guard let userData else {
                        ioNumberDataPackets.pointee = 0
                        return -50
                    }
                    let ctx = Unmanaged<InputContext>.fromOpaque(userData).takeUnretainedValue()
                    let remainingBytes = ctx.totalPCMBytes - ctx.consumedPCMBytes
                    let remainingFrames = remainingBytes / ctx.bytesPerFrame
                    guard remainingFrames > 0, let pcmBase = ctx.pcmBase else {
                        ioNumberDataPackets.pointee = 0
                        ioData.pointee.mBuffers.mData = nil
                        ioData.pointee.mBuffers.mDataByteSize = 0
                        return OpusAudioEncoderBox.needMoreInputStatus
                    }
                    let requestedFrames = Int(ioNumberDataPackets.pointee)
                    let framesToSupply = min(max(requestedFrames, 1), remainingFrames)
                    let byteCount = framesToSupply * ctx.bytesPerFrame
                    let chunkPtr = pcmBase.advanced(by: ctx.consumedPCMBytes)
                    ctx.consumedPCMBytes += byteCount

                    ioNumberDataPackets.pointee = UInt32(framesToSupply)
                    ioData.pointee.mBuffers.mNumberChannels = ctx.channels
                    ioData.pointee.mBuffers.mData = UnsafeMutableRawPointer(mutating: chunkPtr)
                    ioData.pointee.mBuffers.mDataByteSize = UInt32(byteCount)
                    outDataPacketDescription?.pointee = nil
                    return noErr
                }

                let status = AudioConverterFillComplexBuffer(
                    activeConverter,
                    callback,
                    Unmanaged.passUnretained(inputContext).toOpaque(),
                    &ioOutputDataPackets,
                    &outBufferList,
                    &packetDesc
                )
                guard (status == noErr || status == Self.needMoreInputStatus),
                      ioOutputDataPackets == 1,
                      inputContext.consumedPCMBytes > 0 else {
                    return nil
                }
                let byteLen = packetDesc.mDataByteSize > 0
                    ? Int(packetDesc.mDataByteSize)
                    : Int(outBufferList.mBuffers.mDataByteSize)
                let startOffset = Int(packetDesc.mStartOffset)
                guard startOffset >= 0,
                      byteLen >= 1,
                      byteLen <= AudioCapturePacketizer.maxEncodedPacketBytes,
                      startOffset + byteLen <= rawOut.count else {
                    return nil
                }
                isPrimed = true
                let packet = Data(bytes: outBase.advanced(by: startOffset), count: byteLen)
                return EncodeResult(opusPacket: packet, consumedPCMBytes: inputContext.consumedPCMBytes)
            }
        }
    }
}

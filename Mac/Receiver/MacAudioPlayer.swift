import AVFoundation
import Foundation

/// Thread-safe bounded 120 ms (`5_760` stereo frames @ 48 kHz) PCM ring buffer
/// with dynamic A/V lip-sync playout watermark steering (`15ms...90ms`) and drift trimming.
final class AudioPCMRingBuffer: @unchecked Sendable {
    static let sampleRate: Double = 48_000
    static let channels: Int = 2
    static let maxDurationMs: Int = 120
    static let defaultCapacityFrames: Int = 5_760 // 120 ms @ 48 kHz

    let capacityFrames: Int
    private let lock = NSLock()
    private var leftStorage: [Float]
    private var rightStorage: [Float]
    private var readIndex: Int = 0
    private var writeIndex: Int = 0
    private var count: Int = 0
    private var muted: Bool = false
    private var priming: Bool = true
    private(set) var targetBufferedFrames: Int
    private(set) var droppedFrames: UInt64 = 0
    private(set) var driftTrimmedFrames: UInt64 = 0

    init(capacityFrames: Int = AudioPCMRingBuffer.defaultCapacityFrames) {
        let cap = max(240, capacityFrames)
        self.capacityFrames = cap
        self.targetBufferedFrames = min(960, cap) // 20 ms default wired target
        self.leftStorage = [Float](repeating: 0, count: cap)
        self.rightStorage = [Float](repeating: 0, count: cap)
    }

    var availableFrames: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }

    var isMuted: Bool {
        get {
            lock.lock()
            defer { lock.unlock() }
            return muted
        }
        set {
            lock.lock()
            muted = newValue
            if newValue {
                readIndex = 0
                writeIndex = 0
                count = 0
                priming = true
            }
            lock.unlock()
        }
    }

    /// Enqueues interleaved 16-bit signed little-endian PCM bytes (`channels` = 1 or 2).
    func enqueueInterleavedS16LE(_ data: Data, channels: Int = 2) {
        let ch = (channels == 1) ? 1 : 2
        let bytesPerFrame = ch * 2
        let frames = data.count / bytesPerFrame
        guard frames > 0 else { return }

        lock.lock()
        defer { lock.unlock() }
        guard !muted else { return }

        data.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return }
            for i in 0..<frames {
                let offset = i * bytesPerFrame
                let lRaw = Int16(littleEndian: base.loadUnaligned(fromByteOffset: offset, as: Int16.self))
                let rRaw = ch == 2
                    ? Int16(littleEndian: base.loadUnaligned(fromByteOffset: offset + 2, as: Int16.self))
                    : lRaw
                leftStorage[writeIndex] = Float(lRaw) / 32768.0
                rightStorage[writeIndex] = Float(rRaw) / 32768.0
                writeIndex = (writeIndex + 1) % capacityFrames
                if count == capacityFrames {
                    readIndex = (readIndex + 1) % capacityFrames
                    droppedFrames &+= 1
                } else {
                    count += 1
                }
            }
        }
    }

    /// Updates dynamic target watermark and trims oldest excess frames when buffered frames
    /// exceed `trimThresholdFrames` (`target + 25ms`).
    func applyLipSyncWatermark(targetFrames: Int, trimThresholdFrames: Int) {
        lock.lock()
        defer { lock.unlock() }
        let clampedTarget = min(max(targetFrames, 1), capacityFrames)
        targetBufferedFrames = clampedTarget
        let clampedThreshold = min(max(trimThresholdFrames, clampedTarget), capacityFrames)
        if count > clampedThreshold {
            let excess = count - clampedTarget
            if excess > 0 {
                readIndex = (readIndex + excess) % capacityFrames
                count -= excess
                droppedFrames &+= UInt64(excess)
                driftTrimmedFrames &+= UInt64(excess)
            }
        }
    }

    /// Reads up to `frameCount` stereo frames into `leftOut` and `rightOut`,
    /// zero-filling any underrun tail (or holding silence while priming up to `targetBufferedFrames`
    /// when `respectTargetPriming` is enabled).
    @discardableResult
    func render(intoLeft leftOut: UnsafeMutablePointer<Float>,
                right rightOut: UnsafeMutablePointer<Float>,
                frameCount: Int,
                respectTargetPriming: Bool = false) -> Int {
        guard frameCount > 0 else { return 0 }
        lock.lock()
        defer { lock.unlock() }

        if muted || count == 0 {
            if count == 0 {
                priming = true
            }
            leftOut.initialize(repeating: 0, count: frameCount)
            rightOut.initialize(repeating: 0, count: frameCount)
            return 0
        }

        if respectTargetPriming && priming {
            if count < min(targetBufferedFrames, capacityFrames) {
                leftOut.initialize(repeating: 0, count: frameCount)
                rightOut.initialize(repeating: 0, count: frameCount)
                return 0
            }
            priming = false
        }

        let toRead = min(frameCount, count)
        for i in 0..<toRead {
            leftOut[i] = leftStorage[readIndex]
            rightOut[i] = rightStorage[readIndex]
            readIndex = (readIndex + 1) % capacityFrames
        }
        count -= toRead

        if toRead < frameCount {
            if count == 0 {
                priming = true
            }
            (leftOut + toRead).initialize(repeating: 0, count: frameCount - toRead)
            (rightOut + toRead).initialize(repeating: 0, count: frameCount - toRead)
        }
        return toRead
    }

    func reset() {
        lock.lock()
        readIndex = 0
        writeIndex = 0
        count = 0
        priming = true
        lock.unlock()
    }
}

/// Bounded 120 ms `AVAudioEngine` stereo 48 kHz PCM/Opus player for `StreamReceiver`
/// with dynamic A/V lip-sync target watermark steering.
@objc(DisplayWeaveMacAudioPlayer)
final class MacAudioPlayer: NSObject, MacAudioPlaying, @unchecked Sendable {
    let ringBuffer: AudioPCMRingBuffer
    private let lock = NSLock()
    private let decodeLock = NSLock()
    private let opusDecoder = AppleOpusAudioDecoder()
    private var lipSync = AudioLipSyncPolicy()
    private var engine: AVAudioEngine?
    private var sourceNode: AVAudioSourceNode?
    private var configObserver: NSObjectProtocol?
    private var engineStarted = false
    private var starting = false
    private var generation: UInt64 = 0
    private var audioHardwareDisabled = false

    override convenience init() {
        self.init(capacityFrames: AudioPCMRingBuffer.defaultCapacityFrames, disableHardwareOutput: false)
    }

    init(capacityFrames: Int = AudioPCMRingBuffer.defaultCapacityFrames,
         disableHardwareOutput: Bool = false) {
        self.ringBuffer = AudioPCMRingBuffer(capacityFrames: capacityFrames)
        self.audioHardwareDisabled = disableHardwareOutput
        super.init()
    }

    deinit {
        stop()
    }

    var isMuted: Bool {
        get { ringBuffer.isMuted }
        set { ringBuffer.isMuted = newValue }
    }

    var currentTargetBufferedFrames: Int {
        decodeLock.lock()
        defer { decodeLock.unlock() }
        return lipSync.targetBufferedFrames
    }

    func enqueueS16LE(_ pcmData: Data) {
        guard !pcmData.isEmpty, !ringBuffer.isMuted else { return }
        ringBuffer.enqueueInterleavedS16LE(pcmData, channels: 2)
        ensureStartedIfNeeded()
    }

    func enqueueEncodedAudio(
        formatFlags: UInt8,
        payload: Data,
        sampleRate: Int = 48_000,
        channels: Int = 2,
        captureTimestampMs: Int64 = 0,
        arrivalMonoMs: Double = ProcessInfo.processInfo.systemUptime * 1_000.0
    ) {
        guard !payload.isEmpty, !ringBuffer.isMuted else { return }

        decodeLock.lock()
        lipSync.setSampleRate(sampleRate)
        let targetFrames = lipSync.observeAudioArrival(
            captureTimestampMs: captureTimestampMs,
            arrivalMonoMs: arrivalMonoMs
        )
        let trimThreshold = lipSync.driftTrimThresholdFrames
        let pcmData: Data?
        switch formatFlags {
        case UDPMediaAudioPayload.formatPCM16LE:
            pcmData = payload
        case UDPMediaAudioPayload.formatOpus:
            pcmData = opusDecoder.decodeToInterleavedS16LE(
                opusPacket: payload,
                sampleRate: sampleRate,
                channels: channels
            )
        default:
            pcmData = nil
        }
        decodeLock.unlock()

        guard let pcmData, !pcmData.isEmpty else { return }
        ringBuffer.enqueueInterleavedS16LE(pcmData, channels: channels)
        ringBuffer.applyLipSyncWatermark(
            targetFrames: targetFrames,
            trimThresholdFrames: trimThreshold
        )
        ensureStartedIfNeeded()
    }

    func updateVideoPipelineDelay(udpJitterActive: Bool, explicitDelayMs: Double? = nil) {
        decodeLock.lock()
        lipSync.updateTransportMode(udpJitterActive: udpJitterActive, explicitVideoDelayMs: explicitDelayMs)
        let targetFrames = lipSync.targetBufferedFrames
        let trimThreshold = lipSync.driftTrimThresholdFrames
        decodeLock.unlock()
        ringBuffer.applyLipSyncWatermark(targetFrames: targetFrames, trimThresholdFrames: trimThreshold)
    }

    func recordVideoRender(captureTimestampMs: Int64, renderMonoMs: Double) {
        decodeLock.lock()
        lipSync.recordVideoRender(captureTimestampMs: captureTimestampMs, renderMonoMs: renderMonoMs)
        decodeLock.unlock()
    }

    func stop() {
        ringBuffer.reset()
        decodeLock.lock()
        opusDecoder.reset()
        lipSync.reset()
        decodeLock.unlock()

        lock.lock()
        generation &+= 1
        let activeEngine = engine
        let activeNode = sourceNode
        let observer = configObserver
        engine = nil
        sourceNode = nil
        configObserver = nil
        engineStarted = false
        starting = false
        lock.unlock()

        if let observer {
            NotificationCenter.default.removeObserver(observer)
        }
        if let activeEngine {
            activeEngine.stop()
            if let activeNode {
                activeEngine.detach(activeNode)
            }
        }
    }

    private func ensureStartedIfNeeded() {
        lock.lock()
        if engineStarted || starting || audioHardwareDisabled {
            lock.unlock()
            return
        }
        starting = true
        let startGeneration = generation
        lock.unlock()

        guard let format = AVAudioFormat(
            standardFormatWithSampleRate: AudioPCMRingBuffer.sampleRate,
            channels: AVAudioChannelCount(AudioPCMRingBuffer.channels)
        ) else {
            lock.lock()
            starting = false
            if generation == startGeneration {
                audioHardwareDisabled = true
            }
            lock.unlock()
            return
        }

        let ring = self.ringBuffer
        let node = AVAudioSourceNode(format: format) { _, _, frameCount, audioBufferList -> OSStatus in
            let buffers = UnsafeMutableAudioBufferListPointer(audioBufferList)
            let frames = Int(frameCount)
            guard frames > 0, !buffers.isEmpty else { return noErr }
            if buffers.count >= 2,
               let leftPtr = buffers[0].mData?.assumingMemoryBound(to: Float.self),
               let rightPtr = buffers[1].mData?.assumingMemoryBound(to: Float.self) {
                ring.render(intoLeft: leftPtr, right: rightPtr, frameCount: frames, respectTargetPriming: true)
            } else if let interleavedPtr = buffers[0].mData?.assumingMemoryBound(to: Float.self) {
                var tempLeft = [Float](repeating: 0, count: frames)
                var tempRight = [Float](repeating: 0, count: frames)
                tempLeft.withUnsafeMutableBufferPointer { lBuf in
                    tempRight.withUnsafeMutableBufferPointer { rBuf in
                        if let lBase = lBuf.baseAddress, let rBase = rBuf.baseAddress {
                            ring.render(intoLeft: lBase, right: rBase, frameCount: frames, respectTargetPriming: true)
                        }
                    }
                }
                let chCount = max(Int(buffers[0].mNumberChannels), 1)
                for i in 0..<frames {
                    interleavedPtr[i * chCount] = tempLeft[i]
                    if chCount > 1 {
                        interleavedPtr[i * chCount + 1] = tempRight[i]
                    }
                }
            }
            return noErr
        }

        let newEngine = AVAudioEngine()
        newEngine.attach(node)
        newEngine.connect(node, to: newEngine.mainMixerNode, format: format)
        let observer = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: newEngine,
            queue: nil
        ) { [weak self, weak newEngine] _ in
            guard let self, let newEngine else { return }
            self.handleConfigurationChange(for: newEngine)
        }

        let startedOK: Bool
        do {
            try newEngine.start()
            startedOK = true
        } catch {
            startedOK = false
        }

        var engineToTearDown: AVAudioEngine?
        var nodeToDetach: AVAudioSourceNode?
        var observerToRemove: NSObjectProtocol?

        lock.lock()
        starting = false
        if startedOK && generation == startGeneration {
            engine = newEngine
            sourceNode = node
            configObserver = observer
            engineStarted = true
        } else {
            if !startedOK && generation == startGeneration {
                audioHardwareDisabled = true
            }
            engineToTearDown = newEngine
            nodeToDetach = node
            observerToRemove = observer
        }
        lock.unlock()

        if let observerToRemove {
            NotificationCenter.default.removeObserver(observerToRemove)
        }
        if let engineToTearDown {
            engineToTearDown.stop()
            if let nodeToDetach {
                engineToTearDown.detach(nodeToDetach)
            }
        }
    }

    private func handleConfigurationChange(for changedEngine: AVAudioEngine) {
        lock.lock()
        guard engine === changedEngine else {
            lock.unlock()
            return
        }
        let activeNode = sourceNode
        let observer = configObserver
        engine = nil
        sourceNode = nil
        configObserver = nil
        engineStarted = false
        lock.unlock()

        if let observer {
            NotificationCenter.default.removeObserver(observer)
        }
        changedEngine.stop()
        if let activeNode {
            changedEngine.detach(activeNode)
        }
    }
}

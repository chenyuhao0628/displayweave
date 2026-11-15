import AVFoundation
import Foundation

/// Thread-safe bounded 60 ms (`2_880` stereo frames @ 48 kHz) PCM ring buffer.
/// Excess arrivals overwrite the oldest unread frames so audio latency never drifts.
final class AudioPCMRingBuffer: @unchecked Sendable {
    static let sampleRate: Double = 48_000
    static let channels: Int = 2
    static let maxDurationMs: Int = 60
    static let defaultCapacityFrames: Int = 2_880 // 60 ms @ 48 kHz

    let capacityFrames: Int
    private let lock = NSLock()
    private var leftStorage: [Float]
    private var rightStorage: [Float]
    private var readIndex: Int = 0
    private var writeIndex: Int = 0
    private var count: Int = 0
    private var muted: Bool = false
    private(set) var droppedFrames: UInt64 = 0

    init(capacityFrames: Int = AudioPCMRingBuffer.defaultCapacityFrames) {
        let cap = max(240, capacityFrames)
        self.capacityFrames = cap
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
            }
            lock.unlock()
        }
    }

    /// Enqueues interleaved 16-bit signed little-endian stereo PCM bytes (`4` bytes/frame).
    func enqueueInterleavedS16LE(_ data: Data) {
        let frames = data.count / 4
        guard frames > 0 else { return }

        lock.lock()
        defer { lock.unlock() }
        guard !muted else { return }

        data.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return }
            for i in 0..<frames {
                let offset = i * 4
                let lRaw = Int16(littleEndian: base.loadUnaligned(fromByteOffset: offset, as: Int16.self))
                let rRaw = Int16(littleEndian: base.loadUnaligned(fromByteOffset: offset + 2, as: Int16.self))
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

    /// Reads up to `frameCount` stereo frames into `leftOut` and `rightOut`,
    /// zero-filling any underrun tail (or the entire buffer when muted).
    @discardableResult
    func render(intoLeft leftOut: UnsafeMutablePointer<Float>,
                right rightOut: UnsafeMutablePointer<Float>,
                frameCount: Int) -> Int {
        guard frameCount > 0 else { return 0 }
        lock.lock()
        defer { lock.unlock() }

        if muted || count == 0 {
            leftOut.initialize(repeating: 0, count: frameCount)
            rightOut.initialize(repeating: 0, count: frameCount)
            return 0
        }

        let toRead = min(frameCount, count)
        for i in 0..<toRead {
            leftOut[i] = leftStorage[readIndex]
            rightOut[i] = rightStorage[readIndex]
            readIndex = (readIndex + 1) % capacityFrames
        }
        count -= toRead

        if toRead < frameCount {
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
        lock.unlock()
    }
}

/// Bounded 60 ms `AVAudioEngine` stereo 48 kHz PCM player for `StreamReceiver`.
/// Lazily starts CoreAudio output on first audio chunk and stops/mutes cleanly
/// on disconnect, stream reset, or role switch.
@objc(DisplayWeaveMacAudioPlayer)
final class MacAudioPlayer: NSObject, MacAudioPlaying, @unchecked Sendable {
    let ringBuffer: AudioPCMRingBuffer
    private let lock = NSLock()
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

    func enqueueS16LE(_ pcmData: Data) {
        guard !pcmData.isEmpty, !ringBuffer.isMuted else { return }
        ringBuffer.enqueueInterleavedS16LE(pcmData)
        ensureStartedIfNeeded()
    }

    func stop() {
        ringBuffer.reset()
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
                ring.render(intoLeft: leftPtr, right: rightPtr, frameCount: frames)
            } else if let interleavedPtr = buffers[0].mData?.assumingMemoryBound(to: Float.self) {
                var tempLeft = [Float](repeating: 0, count: frames)
                var tempRight = [Float](repeating: 0, count: frames)
                tempLeft.withUnsafeMutableBufferPointer { lBuf in
                    tempRight.withUnsafeMutableBufferPointer { rBuf in
                        if let lBase = lBuf.baseAddress, let rBase = rBuf.baseAddress {
                            ring.render(intoLeft: lBase, right: rBase, frameCount: frames)
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

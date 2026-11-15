import Foundation
import AVFoundation

/// Low-latency 48 kHz stereo PCM audio player backed by `AVAudioEngine`,
/// `AVAudioPlayerNode`, and a preallocated ring buffer strictly bounded to
/// 60 ms (`2,880` frames @ 48 kHz) with trim-oldest overflow recovery.
@objc(DisplayWeaveIOSAudioPlayer)
final class IOSAudioPlayer: NSObject, IOSAudioPlayback {
    static let targetSampleRate: Double = 48_000
    static let targetChannels: AVAudioChannelCount = 2
    /// Hard 60 ms ceiling across scheduled player-node buffers + unread ring frames.
    static let maxTotalLatencyFrames: Int = 2_880 // 60 ms @ 48 kHz
    static let ringCapacity: Int = 2_880
    private static let chunkFrames: Int = 480     // 10 ms per scheduled buffer
    private static let maxInFlightBuffers: Int = 3 // <= 30 ms on AVAudioPlayerNode
    private static let bufferPoolCount: Int = 4

    private let lock = NSLock()
    private let format: AVAudioFormat
    private var engine: AVAudioEngine?
    private var playerNode: AVAudioPlayerNode?
    private var bufferPool: [AVAudioPCMBuffer] = []
    private var bufferInUse: [Bool] = []
    private var configObserver: NSObjectProtocol?

    private var leftRing = [Float](repeating: 0, count: IOSAudioPlayer.ringCapacity)
    private var rightRing = [Float](repeating: 0, count: IOSAudioPlayer.ringCapacity)
    private var readIndex: Int = 0
    private var writeIndex: Int = 0
    private var availableFrames: Int = 0
    private var inFlightBuffers: Int = 0
    private var inFlightFrames: Int = 0
    private var playbackEpoch: UInt64 = 0
    private var stopGeneration: UInt64 = 0
    private var engineRunning: Bool = false
    private var startingEngine: Bool = false

    private final class EngineStateToken {
        var invalidated: Bool = false
    }

    private var scratchLeft = [Float](repeating: 0, count: IOSAudioPlayer.ringCapacity)
    private var scratchRight = [Float](repeating: 0, count: IOSAudioPlayer.ringCapacity)

    override required init() {
        self.format = AVAudioFormat(
            standardFormatWithSampleRate: Self.targetSampleRate,
            channels: Self.targetChannels
        ) ?? AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: Self.targetSampleRate,
            channels: Self.targetChannels,
            interleaved: false
        )!
        super.init()
        allocateBufferPool()
    }

    deinit {
        stop()
    }

    private func allocateBufferPool() {
        bufferPool.removeAll(keepingCapacity: true)
        bufferInUse = [Bool](repeating: false, count: Self.bufferPoolCount)
        for _ in 0..<Self.bufferPoolCount {
            if let buf = AVAudioPCMBuffer(
                pcmFormat: format,
                frameCapacity: AVAudioFrameCount(Self.chunkFrames)
            ) {
                bufferPool.append(buf)
            }
        }
    }

    func enqueuePCM(_ pcmData: Data, sampleRate: Int, channels: Int) {
        guard !pcmData.isEmpty,
              pcmData.count <= 65_536,
              (1...2).contains(channels),
              (8_000...96_000).contains(sampleRate) else { return }
        let bytesPerFrame = channels * 2
        let rawFrameCount = pcmData.count / bytesPerFrame
        guard rawFrameCount > 0 else { return }

        lock.lock()
        let decodedFrames = decodeIntoScratchLocked(
            pcmData: pcmData,
            rawFrameCount: rawFrameCount,
            sampleRate: sampleRate,
            channels: channels
        )
        guard decodedFrames > 0 else {
            lock.unlock()
            return
        }

        // Enforce 60 ms ceiling across in-flight AVAudioPlayerNode frames + ring buffer:
        // trim oldest unread samples first so live audio never drifts behind video.
        let maxRingAllowed = max(0, min(Self.ringCapacity, Self.maxTotalLatencyFrames - inFlightFrames))
        if maxRingAllowed == 0 {
            readIndex = 0
            writeIndex = 0
            availableFrames = 0
            lock.unlock()
            return
        }

        let startOffset: Int
        let framesToWrite: Int
        if decodedFrames >= maxRingAllowed {
            // Incoming burst exceeds remaining budget: drop all older ring samples
            // and keep only the newest `maxRingAllowed` frames.
            readIndex = 0
            writeIndex = 0
            availableFrames = 0
            startOffset = decodedFrames - maxRingAllowed
            framesToWrite = maxRingAllowed
        } else {
            if availableFrames + decodedFrames > maxRingAllowed {
                let trimCount = (availableFrames + decodedFrames) - maxRingAllowed
                readIndex = (readIndex + trimCount) % Self.ringCapacity
                availableFrames -= trimCount
            }
            startOffset = 0
            framesToWrite = decodedFrames
        }

        for i in 0..<framesToWrite {
            let src = startOffset + i
            leftRing[writeIndex] = scratchLeft[src]
            rightRing[writeIndex] = scratchRight[src]
            writeIndex = (writeIndex + 1) % Self.ringCapacity
        }
        availableFrames += framesToWrite

        if engineRunning, let eng = engine, let node = playerNode {
            let schedules = popSchedulesLocked()
            lock.unlock()
            if eng.isRunning {
                if !node.isPlaying { node.play() }
                submitSchedules(schedules)
                return
            }
            lock.lock()
            if self.engine === eng {
                self.engineRunning = false
                self.playbackEpoch &+= 1
                self.inFlightBuffers = 0
                self.inFlightFrames = 0
                for idx in self.bufferInUse.indices {
                    self.bufferInUse[idx] = false
                }
            }
            lock.unlock()
            startOrReplaceEngineAndDrain()
            return
        }
        lock.unlock()
        startOrReplaceEngineAndDrain()
    }

    func stop() {
        lock.lock()
        stopGeneration &+= 1
        playbackEpoch &+= 1
        startingEngine = false
        readIndex = 0
        writeIndex = 0
        availableFrames = 0
        inFlightBuffers = 0
        inFlightFrames = 0
        for idx in bufferInUse.indices {
            bufferInUse[idx] = false
        }
        let oldObserver = configObserver
        configObserver = nil
        let node = playerNode
        let eng = engine
        playerNode = nil
        engine = nil
        engineRunning = false
        lock.unlock()

        if let oldObserver {
            NotificationCenter.default.removeObserver(oldObserver)
        }
        node?.stop()
        eng?.stop()
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
        #endif
    }

    // MARK: - Internal helpers (must hold `lock` for `*Locked` methods)

    private struct PendingSchedule {
        let node: AVAudioPlayerNode
        let buffer: AVAudioPCMBuffer
        let slot: Int
        let frames: Int
        let epoch: UInt64
    }

    private func decodeIntoScratchLocked(
        pcmData: Data,
        rawFrameCount: Int,
        sampleRate: Int,
        channels: Int
    ) -> Int {
        let scale: Float = 1.0 / 32768.0
        return pcmData.withUnsafeBytes { rawBuffer -> Int in
            guard let base = rawBuffer.baseAddress else { return 0 }
            func readSample(_ sampleIndex: Int) -> Float {
                let byteOffset = sampleIndex * 2
                let lo = UInt16(base.load(fromByteOffset: byteOffset, as: UInt8.self))
                let hi = UInt16(base.load(fromByteOffset: byteOffset + 1, as: UInt8.self))
                let signed = Int16(bitPattern: lo | (hi << 8))
                return Float(signed) * scale
            }

            if sampleRate == Int(Self.targetSampleRate) {
                let keepFrames = min(rawFrameCount, Self.ringCapacity)
                let skipFrames = rawFrameCount - keepFrames
                if channels == 2 {
                    for i in 0..<keepFrames {
                        let f = skipFrames + i
                        scratchLeft[i] = readSample(f * 2)
                        scratchRight[i] = readSample(f * 2 + 1)
                    }
                } else {
                    for i in 0..<keepFrames {
                        let sample = readSample(skipFrames + i)
                        scratchLeft[i] = sample
                        scratchRight[i] = sample
                    }
                }
                return keepFrames
            } else {
                let ratio = Double(sampleRate) / Self.targetSampleRate
                let estimatedOut = Int((Double(rawFrameCount) / ratio).rounded(.down))
                guard estimatedOut > 0 else { return 0 }
                let outFrames = min(estimatedOut, Self.ringCapacity)
                let outSkip = estimatedOut - outFrames
                for i in 0..<outFrames {
                    let srcPos = Double(outSkip + i) * ratio
                    let idx0 = min(rawFrameCount - 1, max(0, Int(srcPos)))
                    let idx1 = min(rawFrameCount - 1, idx0 + 1)
                    let frac = Float(srcPos - Double(idx0))
                    if channels == 2 {
                        let l0 = readSample(idx0 * 2)
                        let l1 = readSample(idx1 * 2)
                        let r0 = readSample(idx0 * 2 + 1)
                        let r1 = readSample(idx1 * 2 + 1)
                        scratchLeft[i] = l0 + (l1 - l0) * frac
                        scratchRight[i] = r0 + (r1 - r0) * frac
                    } else {
                        let s0 = readSample(idx0)
                        let s1 = readSample(idx1)
                        let s = s0 + (s1 - s0) * frac
                        scratchLeft[i] = s
                        scratchRight[i] = s
                    }
                }
                return outFrames
            }
        }
    }

    private func startOrReplaceEngineAndDrain() {
        lock.lock()
        if engineRunning, let eng = engine, let node = playerNode {
            let schedules = popSchedulesLocked()
            lock.unlock()
            if eng.isRunning {
                if !node.isPlaying { node.play() }
                submitSchedules(schedules)
            }
            return
        }
        if startingEngine {
            lock.unlock()
            return
        }
        startingEngine = true
        let expectedStopGen = stopGeneration
        let oldObserver = configObserver
        let oldNode = playerNode
        let oldEngine = engine
        configObserver = nil
        playerNode = nil
        engine = nil
        engineRunning = false
        playbackEpoch &+= 1
        inFlightBuffers = 0
        inFlightFrames = 0
        for idx in bufferInUse.indices {
            bufferInUse[idx] = false
        }
        lock.unlock()

        // Tear down previous engine/observer and start the replacement strictly outside
        // `lock` so CoreAudio / NotificationCenter callbacks never invert lock order.
        if let oldObserver {
            NotificationCenter.default.removeObserver(oldObserver)
        }
        oldNode?.stop()
        oldEngine?.stop()

        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try? session.setPreferredSampleRate(Self.targetSampleRate)
            try? session.setPreferredIOBufferDuration(0.010)
            try session.setActive(true)
        } catch {
            Log.info("audio session activation failed: \(error.localizedDescription)")
            lock.lock()
            if stopGeneration == expectedStopGen {
                startingEngine = false
            }
            lock.unlock()
            return
        }
        #endif

        let newEngine = AVAudioEngine()
        let newNode = AVAudioPlayerNode()
        newEngine.attach(newNode)
        newEngine.connect(newNode, to: newEngine.mainMixerNode, format: format)
        newEngine.prepare()

        let stateToken = EngineStateToken()
        let newObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: newEngine,
            queue: nil
        ) { [weak self, weak newEngine] _ in
            guard let self else { return }
            self.lock.lock()
            stateToken.invalidated = true
            if let newEngine, self.engine === newEngine {
                self.engineRunning = false
                self.playbackEpoch &+= 1
                self.inFlightBuffers = 0
                self.inFlightFrames = 0
                for idx in self.bufferInUse.indices {
                    self.bufferInUse[idx] = false
                }
            }
            self.lock.unlock()
        }

        do {
            try newEngine.start()
            newNode.play()
        } catch {
            NotificationCenter.default.removeObserver(newObserver)
            Log.info("AVAudioEngine start failed: \(error.localizedDescription)")
            lock.lock()
            if stopGeneration == expectedStopGen {
                startingEngine = false
            }
            lock.unlock()
            return
        }

        lock.lock()
        let stoppedWhileStarting = (stopGeneration != expectedStopGen)
        if stoppedWhileStarting || stateToken.invalidated {
            if !stoppedWhileStarting {
                startingEngine = false
            }
            lock.unlock()
            NotificationCenter.default.removeObserver(newObserver)
            newNode.stop()
            newEngine.stop()
            if stoppedWhileStarting {
                #if os(iOS)
                try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
                #endif
            }
            return
        }

        playbackEpoch &+= 1
        inFlightBuffers = 0
        inFlightFrames = 0
        for idx in bufferInUse.indices {
            bufferInUse[idx] = false
        }
        engine = newEngine
        playerNode = newNode
        configObserver = newObserver
        engineRunning = true
        startingEngine = false
        let schedules = popSchedulesLocked()
        lock.unlock()

        submitSchedules(schedules)
    }

    private func popSchedulesLocked() -> [PendingSchedule] {
        guard engineRunning, let node = playerNode else { return [] }
        var result: [PendingSchedule] = []
        let epoch = playbackEpoch

        while inFlightBuffers < Self.maxInFlightBuffers, availableFrames > 0 {
            guard let slot = bufferInUse.firstIndex(of: false),
                  slot < bufferPool.count else { break }
            let count = min(Self.chunkFrames, availableFrames)
            guard count > 0 else { break }
            let pcmBuffer = bufferPool[slot]
            guard let channelData = pcmBuffer.floatChannelData else { break }
            pcmBuffer.frameLength = AVAudioFrameCount(count)
            let dstL = channelData[0]
            let dstR = channelData[1]
            for i in 0..<count {
                dstL[i] = leftRing[readIndex]
                dstR[i] = rightRing[readIndex]
                readIndex = (readIndex + 1) % Self.ringCapacity
            }
            availableFrames -= count
            bufferInUse[slot] = true
            inFlightBuffers += 1
            inFlightFrames += count
            result.append(
                PendingSchedule(
                    node: node,
                    buffer: pcmBuffer,
                    slot: slot,
                    frames: count,
                    epoch: epoch
                )
            )
        }
        return result
    }

    private func submitSchedules(_ schedules: [PendingSchedule]) {
        for item in schedules {
            item.node.scheduleBuffer(item.buffer, completionCallbackType: .dataConsumed) { [weak self] _ in
                self?.onBufferConsumed(slot: item.slot, frames: item.frames, epoch: item.epoch)
            }
        }
    }

    private func onBufferConsumed(slot: Int, frames: Int, epoch: UInt64) {
        lock.lock()
        guard playbackEpoch == epoch, engineRunning else {
            lock.unlock()
            return
        }
        if slot < bufferInUse.count {
            bufferInUse[slot] = false
        }
        inFlightBuffers = max(0, inFlightBuffers - 1)
        inFlightFrames = max(0, inFlightFrames - frames)
        let nextSchedules = popSchedulesLocked()
        lock.unlock()

        submitSchedules(nextSchedules)
    }
}

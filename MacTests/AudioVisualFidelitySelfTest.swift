import AVFoundation
import AudioToolbox
import CoreGraphics
import CoreMedia
import Foundation
import VideoToolbox

#if !os(iOS)
@objc protocol IOSAudioPlayback: AnyObject {
    init()
    func enqueuePCM(_ pcmData: Data, sampleRate: Int, channels: Int)
    @objc optional func enqueueEncodedAudio(
        _ payloadData: Data,
        formatFlags: Int,
        sampleRate: Int,
        channels: Int,
        captureTimestampMs: Int64,
        arrivalMonoMs: Double
    )
    @objc optional func updateVideoPipelineDelay(udpJitterActive: Bool, explicitDelayMs: Double)
    @objc optional func recordVideoRender(captureTimestampMs: Int64, renderMonoMs: Double)
    func stop()
}
#endif

private func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        fatalError("AudioVisualFidelitySelfTest failed: \(message)")
    }
}

@main
struct AudioVisualFidelitySelfTest {
    @MainActor
    static func main() async throws {
        try testOpusEncodeDecodeAndPlayersRoundtrip()
        testTCPAudioFramingAndBackpressureDropPolicy()
        testAVLipSyncWatermarkAndClockOffsetCancellation()
        testVirtualDisplayP3PrimariesAndColorNegotiation()
        try testSettledCrispRefreshGateAndLiveVideoToolbox()
        try await testStreamReceiverTCPAudioAndUDPFallbackContinuity()
        print("AudioVisualFidelitySelfTest PASS")
    }

    // MARK: - 1. Opus 48kHz Stereo 20ms Encode -> TCP/UDP Payload -> Mac & iOS Decode Roundtrip

    private static func testOpusEncodeDecodeAndPlayersRoundtrip() throws {
        var packetizer = AudioCapturePacketizer(opusEnabled: true)
        expect(packetizer.isUsingOpus, "AudioToolbox kAudioFormatOpus encoder must be enabled on macOS")

        let macPlayer = MacAudioPlayer(disableHardwareOutput: true)
        let iosPlayer = IOSAudioPlayer(enableHardwareEngine: false)
        defer {
            macPlayer.stop()
            iosPlayer.stop()
        }
        // Set generous 90ms watermark so all 6 packets (120ms, capped/trimmed around 90ms) accumulate cleanly before draining.
        macPlayer.updateVideoPipelineDelay(udpJitterActive: true, explicitDelayMs: 90.0)
        iosPlayer.updateVideoPipelineDelay(udpJitterActive: true, explicitDelayMs: 90.0)
        // Repeat so EMA reaches ~90ms for this bulk roundtrip test:
        for _ in 0..<20 {
            macPlayer.updateVideoPipelineDelay(udpJitterActive: true, explicitDelayMs: 90.0)
            iosPlayer.updateVideoPipelineDelay(udpJitterActive: true, explicitDelayMs: 90.0)
        }

        // Feed 6 x 20ms = 120ms of distinct 440Hz Left + 880Hz Right stereo sine waves
        // in realistic 20ms (960-frame) ScreenCaptureKit callbacks.
        var chunks: [AudioCapturePacketizer.EncodedChunk] = []
        let framesPerCallback = 960
        for callbackIdx in 0..<6 {
            var leftSlice = [Float](repeating: 0, count: framesPerCallback)
            var rightSlice = [Float](repeating: 0, count: framesPerCallback)
            let baseSample = callbackIdx * framesPerCallback
            for i in 0..<framesPerCallback {
                let t = Double(baseSample + i) / 48_000.0
                leftSlice[i] = Float(sin(2.0 * .pi * 440.0 * t) * 0.65)
                rightSlice[i] = Float(sin(2.0 * .pi * 880.0 * t) * 0.45)
            }
            chunks.append(contentsOf: packetizer.ingestFloat32PlanarEncoded(
                left: leftSlice,
                right: rightSlice,
                sampleRate: 48_000
            ))
        }
        expect(packetizer.isUsingOpus, "AudioCapturePacketizer must stay on Opus without falling back to PCM")
        expect(chunks.count == 6, "6 x 20ms callbacks must emit 6 Opus packets (got \(chunks.count))")

        var totalCompressedBytes = 0
        for (idx, chunk) in chunks.enumerated() {
            expect(chunk.formatFlags == UDPMediaAudioPayload.formatOpus,
                   "Opus packetizer must emit formatOpus (1)")
            expect(chunk.frameCount == 960, "each Opus packet covers 960 frames (20ms)")
            expect(!chunk.data.isEmpty && chunk.data.count <= UDPMediaAudioPayload.maxOpusBytes,
                   "Opus packet bytes must fit within 1...1152")
            totalCompressedBytes += chunk.data.count

            let wirePayload = UDPMediaAudioPayload(
                audioSeq: UInt32(idx + 1),
                captureTimestampMs: 1_700_000_010_000 + Int64(idx * 20),
                sampleRate: 48_000,
                channels: 2,
                formatFlags: chunk.formatFlags,
                pcmBytes: chunk.data
            )
            expect(wirePayload.isValid, "encoded Opus UDPMediaAudioPayload must be valid")
            let tcpJson = TCPAudioFrameMessage.encodeJSONData(wirePayload)
            expect(tcpJson != nil && tcpJson!.count <= TCPAudioFrameMessage.maxControlBytes,
                   "TCP audioFrame JSON must stay strictly <= 4096 bytes")
            let roundtripped = try TCPAudioFrameMessage.decode(jsonData: tcpJson!)
            expect(roundtripped == wirePayload, "TCP audioFrame must round-trip Opus payload losslessly")

            let arrivalMono = 1_000.0 + Double(idx * 20)
            macPlayer.enqueueEncodedAudio(
                formatFlags: roundtripped.formatFlags,
                payload: roundtripped.pcmBytes,
                sampleRate: Int(roundtripped.sampleRate),
                channels: Int(roundtripped.channels),
                captureTimestampMs: roundtripped.captureTimestampMs,
                arrivalMonoMs: arrivalMono
            )
            iosPlayer.enqueueEncodedAudio(
                roundtripped.pcmBytes,
                formatFlags: Int(roundtripped.formatFlags),
                sampleRate: Int(roundtripped.sampleRate),
                channels: Int(roundtripped.channels),
                captureTimestampMs: roundtripped.captureTimestampMs,
                arrivalMonoMs: arrivalMono
            )
        }

        // Raw 120ms S16LE would be 23,040 bytes; 128kbps Opus over 120ms is ~1,920 bytes (< 5,000 bytes).
        expect(totalCompressedBytes < 5_000,
               "Opus 128kbps compression must drastically reduce byte volume vs 23,040B S16LE (got \(totalCompressedBytes)B)")

        // Verify MacAudioPlayer decoded non-silent correlated stereo waveform
        expect(macPlayer.ringBuffer.availableFrames >= 1_920,
               "MacAudioPlayer must buffer decoded Opus PCM frames (got \(macPlayer.ringBuffer.availableFrames))")
        var macLeft = [Float](repeating: 0, count: 1_920)
        var macRight = [Float](repeating: 0, count: 1_920)
        let macRendered = macLeft.withUnsafeMutableBufferPointer { lPtr in
            macRight.withUnsafeMutableBufferPointer { rPtr in
                macPlayer.ringBuffer.render(
                    intoLeft: lPtr.baseAddress!,
                    right: rPtr.baseAddress!,
                    frameCount: 1_920,
                    respectTargetPriming: false
                )
            }
        }
        expect(macRendered == 1_920, "MacAudioPlayer must render 1,920 decoded frames")
        let macLeftRms = sqrt(macLeft.reduce(0.0) { $0 + Double($1 * $1) } / Double(macLeft.count))
        let macRightRms = sqrt(macRight.reduce(0.0) { $0 + Double($1 * $1) } / Double(macRight.count))
        expect(macLeftRms > 0.15 && macRightRms > 0.10,
               "decoded Mac Opus RMS must carry clear stereo signal (L=\(macLeftRms), R=\(macRightRms))")

        // Verify IOSAudioPlayer decoded non-silent stereo waveform
        let iosDrained = iosPlayer.drainStereoForTesting(frameCount: 1_920)
        expect(iosDrained.left.count == 1_920 && iosDrained.right.count == 1_920,
               "IOSAudioPlayer must drain 1,920 decoded Opus frames (got \(iosDrained.left.count))")
        let iosLeftRms = sqrt(iosDrained.left.reduce(0.0) { $0 + Double($1 * $1) } / Double(iosDrained.left.count))
        let iosRightRms = sqrt(iosDrained.right.reduce(0.0) { $0 + Double($1 * $1) } / Double(iosDrained.right.count))
        expect(iosLeftRms > 0.15 && iosRightRms > 0.10,
               "decoded iOS Opus RMS must carry clear stereo signal (L=\(iosLeftRms), R=\(iosRightRms))")

        // Verify automatic fallback to 5ms S16LE PCM when Opus is disabled
        packetizer.reset()
        packetizer.setOpusEnabled(false)
        let fallbackTone = (0..<480).map { Float(sin(Double($0) * 0.05) * 0.5) }
        let pcmChunks = packetizer.ingestFloat32PlanarEncoded(
            left: fallbackTone,
            right: fallbackTone,
            sampleRate: 48_000
        )
        expect(pcmChunks.count == 2
               && pcmChunks[0].formatFlags == UDPMediaAudioPayload.formatPCM16LE
               && pcmChunks[0].data.count == 960,
               "disabling Opus must fall back cleanly to 5ms (960B) S16LE PCM chunks")
    }

    // MARK: - 2. TCP Audio Framing & Backpressure Drop Policy

    private static func testTCPAudioFramingAndBackpressureDropPolicy() {
        expect(TCPAudioBackpressurePolicy.shouldSend(
            connectionReady: true, pendingVideoSends: 0, pendingAudioSends: 0, jsonByteCount: 512),
            "idle TCP queue accepts bounded audio frame")
        expect(TCPAudioBackpressurePolicy.shouldSend(
            connectionReady: true, pendingVideoSends: 2, pendingAudioSends: 1, jsonByteCount: 4_096),
            "pendingVideoSends == 2 and pendingAudioSends == 1 at 4096B boundary is allowed")
        expect(!TCPAudioBackpressurePolicy.shouldSend(
            connectionReady: false, pendingVideoSends: 0, pendingAudioSends: 0, jsonByteCount: 256),
            "unready connection must drop outgoing TCP audio")
        expect(!TCPAudioBackpressurePolicy.shouldSend(
            connectionReady: true, pendingVideoSends: 3, pendingAudioSends: 0, jsonByteCount: 256),
            "pendingVideoSends > 2 MUST immediately drop outgoing TCP audio so video/input never stall")
        expect(!TCPAudioBackpressurePolicy.shouldSend(
            connectionReady: true, pendingVideoSends: 0, pendingAudioSends: 2, jsonByteCount: 256),
            "pendingAudioSends >= 2 MUST drop outgoing TCP audio")
        expect(!TCPAudioBackpressurePolicy.shouldSend(
            connectionReady: true, pendingVideoSends: 0, pendingAudioSends: 0, jsonByteCount: 4_097),
            "TCP audio > 4096 bytes MUST be rejected")
        expect(!TCPAudioBackpressurePolicy.shouldSend(
            connectionReady: true, pendingVideoSends: 0, pendingAudioSends: 0, jsonByteCount: 0),
            "empty TCP audio MUST be rejected")
    }

    // MARK: - 3. A/V Lip-Sync Watermark Steering, Clock-Offset Cancellation & Drift Trimming

    private static func testAVLipSyncWatermarkAndClockOffsetCancellation() {
        var policy = AudioLipSyncPolicy()
        expect(policy.maxCapacityFrames == 5_760,
               "max ring capacity must be 120ms = 5,760 stereo frames @ 48kHz")
        expect(policy.minTargetFrames == 720 && policy.maxTargetFrames == 4_320,
               "target playout watermark must clamp to 15ms...90ms (720...4,320 frames)")
        expect(policy.targetBufferedFrames == 960, "default wired TCP target is 20ms (960 frames)")

        policy.updateTransportMode(udpJitterActive: true)
        expect(policy.targetBufferedFrames == 2_160, "switching to UDP jitter mode sets ~45ms target (2,160 frames)")

        // Simulate arbitrary wall-clock offset between Mac sender Date() ms and receiver monotonic ms:
        // Video captured at Mac t=1_700_000_050_000, rendered at receiver mono t=10_065ms
        // Audio captured at Mac t=1_700_000_050_010, arrives at receiver mono t=10_015ms
        // Relative video lead = (10_065 - 1_700_000_050_000) - (10_015 - 1_700_000_050_010) = +60ms!
        for step in 0..<25 {
            let baseCap: Int64 = 1_700_000_050_000 + Int64(step * 20)
            let baseMono: Double = 10_000.0 + Double(step * 20)
            policy.recordVideoRender(captureTimestampMs: baseCap, renderMonoMs: baseMono + 65.0)
            _ = policy.observeAudioArrival(captureTimestampMs: baseCap + 10, arrivalMonoMs: baseMono + 15.0)
        }
        expect(abs(policy.targetDelayMs - 60.0) < 2.0,
               "relative timestamp alignment must converge to 60ms despite huge wall-clock offset (got \(policy.targetDelayMs)ms)")

        // Clamp check: extreme 180ms lag clamps strictly <= 90ms (4,320 frames); 2ms clamps >= 15ms (720 frames)
        var highPolicy = AudioLipSyncPolicy(udpJitterActive: false)
        highPolicy.updateTransportMode(udpJitterActive: true, explicitVideoDelayMs: 180.0)
        expect(highPolicy.targetBufferedFrames == highPolicy.maxTargetFrames, "target clamps <= 90ms (4,320 frames)")

        var lowPolicy = AudioLipSyncPolicy(udpJitterActive: true)
        lowPolicy.updateTransportMode(udpJitterActive: false, explicitVideoDelayMs: 2.0)
        expect(lowPolicy.targetBufferedFrames == lowPolicy.minTargetFrames, "target clamps >= 15ms (720 frames)")

        // Drift trimming test on both MacAudioPlayer and IOSAudioPlayer:
        // Wired TCP mode: target = 20ms (960 frames), drift threshold = 45ms (2,160 frames).
        let macPlayer = MacAudioPlayer(disableHardwareOutput: true)
        let iosPlayer = IOSAudioPlayer(enableHardwareEngine: false)
        defer {
            macPlayer.stop()
            iosPlayer.stop()
        }
        macPlayer.updateVideoPipelineDelay(udpJitterActive: false, explicitDelayMs: 20.0)
        iosPlayer.updateVideoPipelineDelay(udpJitterActive: false, explicitDelayMs: 20.0)

        let chunk5ms = Data(repeating: 0x04, count: 960) // 240 frames (5ms)
        // Enqueue 12 x 5ms = 60ms (2,880 frames > 45ms threshold)
        for seq in 1...12 {
            let capMs = 1_700_000_100_000 + Int64(seq * 5)
            let monoMs = 5_000.0 + Double(seq * 5)
            macPlayer.enqueueEncodedAudio(
                formatFlags: UDPMediaAudioPayload.formatPCM16LE,
                payload: chunk5ms,
                sampleRate: 48_000,
                channels: 2,
                captureTimestampMs: capMs,
                arrivalMonoMs: monoMs
            )
            iosPlayer.enqueueEncodedAudio(
                chunk5ms,
                formatFlags: Int(UDPMediaAudioPayload.formatPCM16LE),
                sampleRate: 48_000,
                channels: 2,
                captureTimestampMs: capMs,
                arrivalMonoMs: monoMs
            )
        }
        expect(macPlayer.ringBuffer.driftTrimmedFrames > 0 && macPlayer.ringBuffer.availableFrames <= 2_160,
               "MacAudioPlayer must trim excess drift back to target watermark (avail=\(macPlayer.ringBuffer.availableFrames), trimmed=\(macPlayer.ringBuffer.driftTrimmedFrames))")
        expect(iosPlayer.driftTrimmedFrames > 0 && iosPlayer.totalBufferedFrames <= 2_160,
               "IOSAudioPlayer must trim excess drift back to target watermark (avail=\(iosPlayer.totalBufferedFrames), trimmed=\(iosPlayer.driftTrimmedFrames))")
    }

    // MARK: - 4. Virtual Display P3 Primaries & StreamConfig Color Negotiation

    private static func testVirtualDisplayP3PrimariesAndColorNegotiation() {
        let descriptor = CGVirtualDisplayDescriptor()
        VirtualDisplayColorPolicy.applyDisplayP3Primaries(to: descriptor)
        expect(abs(descriptor.redPrimary.x - 0.680) < 1e-6 && abs(descriptor.redPrimary.y - 0.320) < 1e-6,
               "CGVirtualDisplayDescriptor redPrimary must be Display P3 (0.680, 0.320)")
        expect(abs(descriptor.greenPrimary.x - 0.265) < 1e-6 && abs(descriptor.greenPrimary.y - 0.690) < 1e-6,
               "CGVirtualDisplayDescriptor greenPrimary must be Display P3 (0.265, 0.690)")
        expect(abs(descriptor.bluePrimary.x - 0.150) < 1e-6 && abs(descriptor.bluePrimary.y - 0.060) < 1e-6,
               "CGVirtualDisplayDescriptor bluePrimary must be Display P3 (0.150, 0.060)")
        expect(abs(descriptor.whitePoint.x - 0.3127) < 1e-6 && abs(descriptor.whitePoint.y - 0.3290) < 1e-6,
               "CGVirtualDisplayDescriptor whitePoint must be D65 (0.3127, 0.3290)")

        let cfgP3 = StreamConfigMessage(
            codec: .hevc,
            fps: 60,
            width: 2560,
            height: 1600,
            bitrate: 24_000_000,
            transport: "wifi",
            colorSpace: "displayP3"
        )
        let obj = try! JSONSerialization.jsonObject(with: Data(cfgP3.json.utf8)) as! [String: Any]
        expect(obj["colorSpace"] as? String == "displayP3",
               "StreamConfigMessage must serialize colorSpace=displayP3")
    }

    // MARK: - 5. Settled Crisp Text Refresh Policy & Live VideoToolbox Verification

    private static func testSettledCrispRefreshGateAndLiveVideoToolbox() throws {
        expect(abs(CaptureStaticFrameGate.defaultCrispRefreshDelay - 0.18) < 1e-6,
               "settled crisp text refresh delay must default to 180ms")

        for codecType in [kCMVideoCodecType_HEVC, kCMVideoCodecType_H264] {
        for lowLatency in [false, true] {
            let box = CrispEncodedCounter()
            var session: VTCompressionSession?
            var spec: [CFString: Any] = [:]
            if lowLatency {
                spec[kVTVideoEncoderSpecification_EnableLowLatencyRateControl] = kCFBooleanTrue
            }
            let status = VTCompressionSessionCreate(
                allocator: kCFAllocatorDefault,
                width: 640,
                height: 360,
                codecType: codecType,
                encoderSpecification: spec as CFDictionary,
                imageBufferAttributes: nil,
                compressedDataAllocator: nil,
                outputCallback: { refcon, _, encodeStatus, flags, sampleBuffer in
                    guard let refcon else { return }
                    let counter = Unmanaged<CrispEncodedCounter>.fromOpaque(refcon).takeUnretainedValue()
                    counter.record(status: encodeStatus, flags: flags, sampleBuffer: sampleBuffer)
                },
                refcon: Unmanaged.passUnretained(box).toOpaque(),
                compressionSessionOut: &session
            )
            guard status == noErr, let session else {
                continue
            }
            defer { VTCompressionSessionInvalidate(session) }

            let bitrate = 12_000_000
            let fps = 60
            let vbvLimits = StreamEncodingPolicy.dataRateLimits(bitrate: bitrate, fps: fps)
            VTSessionSetProperty(session, key: kVTCompressionPropertyKey_RealTime, value: kCFBooleanTrue)
            VTSessionSetProperty(session, key: kVTCompressionPropertyKey_AllowFrameReordering, value: kCFBooleanFalse)
            VTSessionSetProperty(session, key: kVTCompressionPropertyKey_AverageBitRate, value: bitrate as CFNumber)
            VTSessionSetProperty(session, key: kVTCompressionPropertyKey_DataRateLimits, value: vbvLimits as CFArray)
            VTSessionSetProperty(session, key: kVTCompressionPropertyKey_PrioritizeEncodingSpeedOverQuality, value: kCFBooleanTrue)
            VTCompressionSessionPrepareToEncodeFrames(session)

            var pixel: CVPixelBuffer?
            guard CVPixelBufferCreate(kCFAllocatorDefault, 640, 360, kCVPixelFormatType_32BGRA, nil, &pixel) == kCVReturnSuccess,
                  let pixel else {
                fatalError("CVPixelBufferCreate failed")
            }
            fillCrispTextLikePattern(pixel)

            // Encode 3 motion frames, 1 settled crisp refresh frame, and 2 post-refresh frames
            for idx in 0..<6 {
                let pts = CMTime(value: Int64(idx), timescale: 60)
                if idx == 3 {
                    SettledCrispRefreshEncoderPolicy.withCrispRefreshHints(
                        encoder: session,
                        enabled: true,
                        restoreSpeedOverQuality: true,
                        restoreBitrate: bitrate,
                        restoreVBVLimits: vbvLimits
                    ) {
                        var activeQPRef: Unmanaged<CFTypeRef>?
                        let copyActiveStatus = VTSessionCopyProperty(
                            session,
                            key: kVTCompressionPropertyKey_MaxAllowedFrameQP,
                            allocator: nil,
                            valueOut: &activeQPRef
                        )
                        let activeQP = (activeQPRef?.takeRetainedValue() as? NSNumber)?.intValue
                        expect(copyActiveStatus == noErr && activeQP == SettledCrispRefreshEncoderPolicy.settledMaxAllowedFrameQP,
                               "inside withCrispRefreshHints (lowLatency=\(lowLatency)), MaxAllowedFrameQP must be 20 (got \(String(describing: activeQP)))")
                        _ = VTCompressionSessionEncodeFrame(
                            session,
                            imageBuffer: pixel,
                            presentationTimeStamp: pts,
                            duration: CMTime(value: 1, timescale: 60),
                            frameProperties: nil,
                            sourceFrameRefcon: nil,
                            infoFlagsOut: nil
                        )
                    }
                    var restoredQPRef: Unmanaged<CFTypeRef>?
                    let copyRestoredStatus = VTSessionCopyProperty(
                        session,
                        key: kVTCompressionPropertyKey_MaxAllowedFrameQP,
                        allocator: nil,
                        valueOut: &restoredQPRef
                    )
                    let restoredQP = (restoredQPRef?.takeRetainedValue() as? NSNumber)?.intValue
                    expect(copyRestoredStatus == noErr
                           && restoredQP != SettledCrispRefreshEncoderPolicy.settledMaxAllowedFrameQP
                           && restoredQP == SettledCrispRefreshEncoderPolicy.defaultMaxAllowedFrameQPCeiling,
                           "after withCrispRefreshHints exits (lowLatency=\(lowLatency)), MaxAllowedFrameQP must restore to 51, never stay stuck at 20 (got \(String(describing: restoredQP)))")
                } else {
                    let props = idx == 0 ? ([kVTEncodeFrameOptionKey_ForceKeyFrame: true] as CFDictionary) : nil
                    _ = VTCompressionSessionEncodeFrame(
                        session,
                        imageBuffer: pixel,
                        presentationTimeStamp: pts,
                        duration: CMTime(value: 1, timescale: 60),
                        frameProperties: props,
                        sourceFrameRefcon: nil,
                        infoFlagsOut: nil
                    )
                }
            }
            VTCompressionSessionCompleteFrames(session, untilPresentationTimeStamp: .invalid)
            expect(box.encodedCount == 6 && box.droppedCount == 0,
                   "SettledCrispRefreshEncoderPolicy (codec=\(codecType), lowLatency=\(lowLatency)) must encode all 6 frames with 0 VBV drops (encoded=\(box.encodedCount), dropped=\(box.droppedCount))")

            // Verify explicit valid caller MaxAllowedFrameQP (e.g. 36) is also preserved & restored
            if VTSessionSetProperty(session, key: kVTCompressionPropertyKey_MaxAllowedFrameQP, value: 36 as CFNumber) == noErr {
                SettledCrispRefreshEncoderPolicy.withCrispRefreshHints(
                    encoder: session,
                    enabled: true,
                    restoreSpeedOverQuality: true,
                    restoreBitrate: bitrate,
                    restoreVBVLimits: vbvLimits
                ) {}
                var customQPRef: Unmanaged<CFTypeRef>?
                let customStatus = VTSessionCopyProperty(
                    session,
                    key: kVTCompressionPropertyKey_MaxAllowedFrameQP,
                    allocator: nil,
                    valueOut: &customQPRef
                )
                let customQP = (customQPRef?.takeRetainedValue() as? NSNumber)?.intValue
                expect(customStatus == noErr && customQP == 36,
                       "explicit MaxAllowedFrameQP=36 must restore back to 36 (got \(String(describing: customQP)))")
            }
        }
        }
    }

    private final class CrispEncodedCounter {
        private let lock = NSLock()
        var encodedCount = 0
        var droppedCount = 0

        func record(status: OSStatus, flags: VTEncodeInfoFlags, sampleBuffer: CMSampleBuffer?) {
            lock.lock()
            defer { lock.unlock() }
            if status != noErr || flags.contains(.frameDropped) || sampleBuffer == nil {
                droppedCount += 1
            } else {
                encodedCount += 1
            }
        }
    }

    private static func fillCrispTextLikePattern(_ pixel: CVPixelBuffer) {
        CVPixelBufferLockBaseAddress(pixel, [])
        defer { CVPixelBufferUnlockBaseAddress(pixel, []) }
        let width = CVPixelBufferGetWidth(pixel)
        let height = CVPixelBufferGetHeight(pixel)
        let stride = CVPixelBufferGetBytesPerRow(pixel)
        let base = CVPixelBufferGetBaseAddress(pixel)!.assumingMemoryBound(to: UInt8.self)
        for y in 0..<height {
            for x in 0..<width {
                let glyph = ((x % 7 == 0) || (y % 11 == 0)) && ((x + y) % 3 != 0)
                let v: UInt8 = glyph ? 245 : 24
                let offset = y * stride + x * 4
                base[offset] = v
                base[offset + 1] = v
                base[offset + 2] = v
                base[offset + 3] = 255
            }
        }
    }

    // MARK: - 6. StreamReceiver Live TCP Audio + Opus + Deduplication

    @MainActor
    private static func testStreamReceiverTCPAudioAndUDPFallbackContinuity() async throws {
        let spyAudio = SpyMacAudioPlayer()
        let receiver = StreamReceiver(
            hardwareHEVCDecode: false,
            videoRenderer: NullTestVideoRenderer(),
            audioPlayer: spyAudio,
            securityProvider: { .legacy }
        )
        receiver.configure(
            panel: PanelAnnouncement(
                pixelsWide: 1280,
                pixelsHigh: 720,
                scale: 1,
                pointsWide: 1280,
                pointsHigh: 720,
                millimetersWide: 340,
                millimetersHigh: 190
            ),
            name: "AudioVisualTest",
            maxFps: 60
        )
        receiver.start(port: 0, advertiseService: false)
        defer { receiver.stop() }

        for _ in 0..<80 {
            if receiver.listeningPort != 0 { break }
            try await Task.sleep(for: .milliseconds(25))
        }
        let boundPort = receiver.listeningPort
        expect(boundPort > 0, "StreamReceiver must bind ephemeral port")

        try await Task.detached {
            let peer = try ReceiverTestPeer(port: boundPort)
            let hello = try peer.hello()
            let caps = (hello["capabilities"] as? [String]) ?? []
            expect(caps.contains(AppleVideoPolicy.tcpAudioCapability),
                   "StreamReceiver hello must advertise tcpAudioV1")
            expect(caps.contains(AppleVideoPolicy.audioOpusCapability),
                   "StreamReceiver hello must advertise audioOpusV1")

            var packetizer = AudioCapturePacketizer(opusEnabled: true)
            let tone = (0..<1_440).map { Float(sin(Double($0) * 0.08) * 0.5) }
            let opusChunk = packetizer.ingestFloat32PlanarEncoded(left: tone, right: tone, sampleRate: 48_000)[0]
            let opusPayload = UDPMediaAudioPayload(
                audioSeq: 1,
                captureTimestampMs: 1_700_000_200_000,
                sampleRate: 48_000,
                channels: 2,
                formatFlags: UDPMediaAudioPayload.formatOpus,
                pcmBytes: opusChunk.data
            )
            let pcmPayload = UDPMediaAudioPayload(
                audioSeq: 2,
                captureTimestampMs: 1_700_000_200_020,
                sampleRate: 48_000,
                channels: 2,
                formatFlags: UDPMediaAudioPayload.formatPCM16LE,
                pcmBytes: Data(repeating: 0x10, count: 960)
            )

            try peer.write(ReceiverFrameDecoder.frame(TCPAudioFrameMessage.encodeJSONData(opusPayload)!))
            try peer.write(ReceiverFrameDecoder.frame(TCPAudioFrameMessage.encodeJSONData(pcmPayload)!))
            // Duplicate seq=2 must be deduplicated by StreamReceiver
            try peer.write(ReceiverFrameDecoder.frame(TCPAudioFrameMessage.encodeJSONData(pcmPayload)!))

            expect(spyAudio.waitForPackets(count: 2, timeout: 2.0),
                   "StreamReceiver must deliver both Opus and PCM tcpAudioV1 packets to audioPlayer")
            try await Task.sleep(for: .milliseconds(50))
            expect(spyAudio.receivedFormats == [UDPMediaAudioPayload.formatOpus, UDPMediaAudioPayload.formatPCM16LE],
                   "StreamReceiver must deduplicate repeated audioSeq and preserve formatFlags (got \(spyAudio.receivedFormats))")
            expect(spyAudio.receivedCaptureTimestamps == [1_700_000_200_000, 1_700_000_200_020],
                   "StreamReceiver must forward captureTimestampMs intact")
        }.value
    }

    private final class NullTestVideoRenderer: MacVideoRendering {
        var status: AVQueuedSampleBufferRenderingStatus { .rendering }
        var isReadyForMoreMediaData: Bool { true }
        func enqueue(_ sample: CMSampleBuffer) {}
        func flush(removingDisplayedImage: Bool) {}
    }

    private final class SpyMacAudioPlayer: MacAudioPlaying, @unchecked Sendable {
        private let lock = NSLock()
        private let sem = DispatchSemaphore(value: 0)
        var isMuted: Bool = false
        private(set) var receivedFormats: [UInt8] = []
        private(set) var receivedCaptureTimestamps: [Int64] = []

        func enqueueS16LE(_ pcmData: Data) {
            lock.lock()
            receivedFormats.append(UDPMediaAudioPayload.formatPCM16LE)
            receivedCaptureTimestamps.append(0)
            lock.unlock()
            sem.signal()
        }

        func enqueueEncodedAudio(
            formatFlags: UInt8,
            payload: Data,
            sampleRate: Int,
            channels: Int,
            captureTimestampMs: Int64,
            arrivalMonoMs: Double
        ) {
            lock.lock()
            receivedFormats.append(formatFlags)
            receivedCaptureTimestamps.append(captureTimestampMs)
            lock.unlock()
            sem.signal()
        }

        func updateVideoPipelineDelay(udpJitterActive: Bool, explicitDelayMs: Double?) {}
        func recordVideoRender(captureTimestampMs: Int64, renderMonoMs: Double) {}
        func stop() {}

        func waitForPackets(count: Int, timeout: TimeInterval) -> Bool {
            let deadline = Date().addingTimeInterval(timeout)
            for _ in 0..<count {
                let remaining = deadline.timeIntervalSinceNow
                if remaining <= 0 || sem.wait(timeout: .now() + remaining) != .success {
                    return false
                }
            }
            return true
        }
    }
}

import Foundation
import VideoToolbox

/// Opt-in, offscreen probe. No capture, virtual display, window, or preferences.
/// The current host's codec timing is not a prediction for another GPU/OS.
private final class ProbeStats: @unchecked Sendable {
    let lock = NSLock()
    var pending = 0
    var peak = 0
    var output = 0
    var failed = 0
    var skipped = 0
    var maxSubmitMs = 0.0
    var latency: [Double] = [] // at most 180 samples per bounded run
}

@main enum Mac4KEncoderProbe {
    static func main() throws {
        let bitrate = CommandLine.arguments.dropFirst().first.flatMap(Int.init) ?? 49_766_400
        precondition((8_000_000...100_000_000).contains(bitrate))
        try run(budget: 1, frameDelayLimit: 0, bitrate: bitrate)
        try run(budget: SendQueuePolicy.encodeBudget(fps: 60),
                frameDelayLimit: SendQueuePolicy.frameDelayLimit(fps: 60), bitrate: bitrate)
        try run(budget: SendQueuePolicy.encodeBudget(fps: 60),
                frameDelayLimit: SendQueuePolicy.frameDelayLimit(fps: 60), bitrate: bitrate, offload: true)
    }

    static func run(budget: Int, frameDelayLimit: Int, bitrate: Int, offload: Bool = false) throws {
        let worker = EncoderWorkQueue()
        let width = 3840, height = 2160, frames = 180, fps = 60
        var session: VTCompressionSession?
        let spec: [CFString: Any] = [kVTVideoEncoderSpecification_EnableLowLatencyRateControl: true,
            kVTVideoEncoderSpecification_EnableHardwareAcceleratedVideoEncoder: true]
        let created = VTCompressionSessionCreate(allocator: nil, width: Int32(width), height: Int32(height),
            codecType: kCMVideoCodecType_H264, encoderSpecification: spec as CFDictionary,
            imageBufferAttributes: nil, compressedDataAllocator: nil, outputCallback: nil,
            refcon: nil, compressionSessionOut: &session)
        guard created == noErr, let session else {
            print("SKIP 4K H.264 low-latency encoder unavailable on this host: \(created)"); return
        }
        defer { VTCompressionSessionInvalidate(session) }
        let properties: [CFString: Any] = [
            kVTCompressionPropertyKey_RealTime: true,
            kVTCompressionPropertyKey_AllowFrameReordering: false,
            kVTCompressionPropertyKey_ProfileLevel: kVTProfileLevel_H264_High_AutoLevel,
            kVTCompressionPropertyKey_MaxFrameDelayCount: frameDelayLimit,
            kVTCompressionPropertyKey_AverageBitRate: bitrate,
            kVTCompressionPropertyKey_DataRateLimits: [max(bitrate / 8, 1), 1],
            kVTCompressionPropertyKey_ExpectedFrameRate: fps,
            kVTCompressionPropertyKey_MaxKeyFrameInterval: 120,
            kVTCompressionPropertyKey_MaxKeyFrameIntervalDuration: 2,
            kVTCompressionPropertyKey_PrioritizeEncodingSpeedOverQuality: true]
        for (key, value) in properties {
            let status = VTSessionSetProperty(session, key: key, value: value as CFTypeRef)
            if status != noErr { print("PROPERTY \(key) status=\(status)") }
        }
        VTCompressionSessionPrepareToEncodeFrames(session)
        var hardwareValue: Unmanaged<CFTypeRef>?
        let hardwareStatus = VTSessionCopyProperty(session, key: kVTCompressionPropertyKey_UsingHardwareAcceleratedVideoEncoder,
                              allocator: nil, valueOut: &hardwareValue)
        let hardware = hardwareValue?.takeRetainedValue()
        var pool: CVPixelBufferPool?
        let attributes: [CFString: Any] = [kCVPixelBufferWidthKey: width,
            kCVPixelBufferHeightKey: height,
            kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
            kCVPixelBufferIOSurfacePropertiesKey: [:]]
        precondition(CVPixelBufferPoolCreate(nil, nil, attributes as CFDictionary, &pool) == kCVReturnSuccess)
        let stats = ProbeStats()
        let begin = ProcessInfo.processInfo.systemUptime
        for frame in 0..<frames {
            let due = begin + Double(frame) / Double(fps)
            let delay = due - ProcessInfo.processInfo.systemUptime
            if delay > 0 { Thread.sleep(forTimeInterval: delay) }
            let skip = stats.lock.withLock {
                if SendQueuePolicy.shouldDrop(pendingSends: 0, pendingEncodes: stats.pending,
                                              sendBudget: 3, encodeBudget: budget) {
                    stats.skipped += 1; return true
                }
                stats.pending += 1; stats.peak = max(stats.peak, stats.pending); return false
            }
            if skip { continue }
            var pixel: CVPixelBuffer?
            let result = CVPixelBufferPoolCreatePixelBufferWithAuxAttributes(nil, pool!,
                [kCVPixelBufferPoolAllocationThresholdKey: 3] as CFDictionary, &pixel)
            guard result == kCVReturnSuccess, let pixel else {
                stats.lock.withLock { stats.pending -= 1; stats.failed += 1 }; continue
            }
            // Simple moving 4K luma block, not a real desktop complexity claim.
            CVPixelBufferLockBaseAddress(pixel, [])
            let stride = CVPixelBufferGetBytesPerRowOfPlane(pixel, 0)
            let base = CVPixelBufferGetBaseAddressOfPlane(pixel, 0)!
            memset(base, 64, stride * height)
            let chromaStride = CVPixelBufferGetBytesPerRowOfPlane(pixel, 1)
            memset(CVPixelBufferGetBaseAddressOfPlane(pixel, 1)!, 128, chromaStride * height / 2)
            let left = (frame * 24) % (width - 384)
            for row in 800..<1184 { memset(base.advanced(by: row * stride + left), 210, 384) }
            CVPixelBufferUnlockBaseAddress(pixel, [])
            let submission = EncoderFrameSubmission(encoder: session, pixels: pixel, properties: nil)
            let encode: @Sendable () -> Void = {
                let start = ProcessInfo.processInfo.systemUptime
                let status = VTCompressionSessionEncodeFrame(submission.encoder, imageBuffer: submission.pixels,
                    presentationTimeStamp: CMTime(value: Int64(frame), timescale: 60),
                    duration: CMTime(value: 1, timescale: 60), frameProperties: nil, infoFlagsOut: nil) { status, _, sample in
                    stats.lock.withLock {
                        stats.pending -= 1
                        if status == noErr, sample != nil { stats.output += 1 }
                        else { stats.failed += 1 }
                        stats.latency.append((ProcessInfo.processInfo.systemUptime - start) * 1_000)
                    }
                }
                stats.lock.withLock {
                    stats.maxSubmitMs = max(stats.maxSubmitMs, (ProcessInfo.processInfo.systemUptime - start) * 1_000)
                    if status != noErr { stats.pending -= 1; stats.failed += 1 }
                }
            }
            if offload {
                if !worker.submit(limit: budget, encode) {
                    stats.lock.withLock { stats.pending -= 1; stats.skipped += 1 }
                }
            } else { encode() }
        }
        let drained = worker.perform { VTCompressionSessionCompleteFrames(session, untilPresentationTimeStamp: .invalid) }
        precondition(drained == noErr)

        let elapsed = ProcessInfo.processInfo.systemUptime - begin
        stats.lock.withLock {
            let sorted = stats.latency.sorted()
            let p50 = sorted.isEmpty ? 0 : sorted[sorted.count / 2]
            let p95 = sorted.isEmpty ? 0 : sorted[min(sorted.count - 1, sorted.count * 95 / 100)]
            print("4K-PROBE offload=\(offload) hardware=\(hardware ?? "unknown" as CFString) hardwareQueryStatus=\(hardwareStatus) budget=\(budget) frameDelayLimit=\(frameDelayLimit) captures=\(frames) encoded=\(stats.output) skipped=\(stats.skipped) failed=\(stats.failed) pendingPeak=\(stats.peak) outputFps=\(String(format: "%.2f", Double(stats.output) / elapsed)) encodeP50Ms=\(String(format: "%.2f", p50)) encodeP95Ms=\(String(format: "%.2f", p95)) submitMaxMs=\(String(format: "%.2f", stats.maxSubmitMs))")
            precondition(stats.pending == 0 && stats.peak <= budget && stats.failed == 0)
        }
    }
}

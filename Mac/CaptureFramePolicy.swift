import CoreGraphics
import CoreMedia
import Foundation
import VideoToolbox

enum CaptureStaticFramePolicy {
    /// Tightened ScreenCaptureKit queue depth (from 8 to 4) to reduce worst-case
    /// capture-side buffering latency while preserving headroom for asynchronous
    /// VideoToolbox submission and keyframe replay.
    static let defaultQueueDepth = 4

    /// Inspects `SCStreamFrameInfo.dirtyRects` attachment values (`[NSValue]` or
    /// `[NSDictionary]` representations of `CGRect`).
    /// Returns `true` when at least one non-empty dirty rectangle is present, or
    /// fail-safes to `true` when the attachment is absent or unrecognized.
    static func hasNonEmptyDirtyRects(_ attachmentValue: Any?) -> Bool {
        guard let attachmentValue else { return true }
        guard let elements = attachmentValue as? [Any] else { return true }
        if elements.isEmpty { return false }
        for element in elements {
            if let dict = element as? NSDictionary {
                guard let rect = CGRect(dictionaryRepresentation: dict) else {
                    return true
                }
                if !rect.isNull, !rect.isEmpty, rect.width > 0, rect.height > 0 {
                    return true
                }
            } else if let value = element as? NSValue {
                let rect = value.rectValue
                if !rect.isNull, !rect.isEmpty, rect.width > 0, rect.height > 0 {
                    return true
                }
            } else {
                return true
            }
        }
        return false
    }
}

/// Stateful gate for skipping redundant static desktop captures without starving:
/// 1. The initial frame of any new connection / encoder / stream configuration
///    (protecting `ReceiverFirstVideoDeadline` and Android V2 `awaitingFirstFrame`),
/// 2. Pending or in-flight keyframe recovery requests,
/// 3. Post-motion quality settling frames (`settlingTailFrames`),
/// 4. One settled high-clarity text refresh (`~180ms` after active motion stops),
/// 5. Periodic static keepalive refresh (`maxStaticRefreshInterval`).
struct CaptureStaticFrameGate: Sendable {
    static let defaultCrispRefreshDelay: TimeInterval = 0.18

    struct AdmissionDecision: Equatable, Sendable {
        let shouldEncode: Bool
        let isSettledCrispRefresh: Bool
    }

    let settlingTailFrames: Int
    let crispRefreshDelay: TimeInterval
    let maxStaticRefreshInterval: TimeInterval

    private(set) var hasEncodedFrameInCurrentConfig = false
    private(set) var remainingSettlingFrames = 0
    private(set) var lastAdmittedUptime: TimeInterval?
    private(set) var lastMotionUptime: TimeInterval?
    private(set) var pendingCrispRefresh = false
    private(set) var crispRefreshCount = 0
    private(set) var skippedStaticFrames = 0

    init(
        settlingTailFrames: Int = 1,
        crispRefreshDelay: TimeInterval = CaptureStaticFrameGate.defaultCrispRefreshDelay,
        maxStaticRefreshInterval: TimeInterval = 0.5
    ) {
        self.settlingTailFrames = max(0, settlingTailFrames)
        self.crispRefreshDelay = max(0.05, crispRefreshDelay)
        self.maxStaticRefreshInterval = max(0.05, maxStaticRefreshInterval)
    }

    mutating func resetForNewConfiguration() {
        hasEncodedFrameInCurrentConfig = false
        remainingSettlingFrames = settlingTailFrames
        lastAdmittedUptime = nil
        lastMotionUptime = nil
        pendingCrispRefresh = false
    }

    mutating func markFrameEncoded() {
        hasEncodedFrameInCurrentConfig = true
    }

    mutating func evaluate(
        hasDirtyRects: Bool,
        requiresKeyframe: Bool,
        nowUptime: TimeInterval
    ) -> AdmissionDecision {
        guard nowUptime.isFinite else {
            return AdmissionDecision(shouldEncode: true, isSettledCrispRefresh: false)
        }
        if !hasEncodedFrameInCurrentConfig || requiresKeyframe || hasDirtyRects {
            remainingSettlingFrames = settlingTailFrames
            lastAdmittedUptime = nowUptime
            if hasDirtyRects {
                lastMotionUptime = nowUptime
                pendingCrispRefresh = true
            }
            return AdmissionDecision(shouldEncode: true, isSettledCrispRefresh: false)
        }
        if remainingSettlingFrames > 0 {
            remainingSettlingFrames -= 1
            lastAdmittedUptime = nowUptime
            return AdmissionDecision(shouldEncode: true, isSettledCrispRefresh: false)
        }
        if pendingCrispRefresh,
           let motionAt = lastMotionUptime,
           nowUptime >= motionAt,
           nowUptime - motionAt >= crispRefreshDelay {
            pendingCrispRefresh = false
            crispRefreshCount += 1
            lastAdmittedUptime = nowUptime
            return AdmissionDecision(shouldEncode: true, isSettledCrispRefresh: true)
        }
        if let last = lastAdmittedUptime,
           nowUptime >= last,
           nowUptime - last < maxStaticRefreshInterval {
            skippedStaticFrames += 1
            return AdmissionDecision(shouldEncode: false, isSettledCrispRefresh: false)
        }
        lastAdmittedUptime = nowUptime
        return AdmissionDecision(shouldEncode: true, isSettledCrispRefresh: false)
    }

    /// Invoked by the sender's `180ms` post-motion timer when ScreenCaptureKit stops
    /// emitting callbacks on a static desktop. Admits at most one crisp refresh per
    /// motion burst and becomes a no-op if an SCK static callback already satisfied it.
    mutating func pollTimerCrispRefresh(nowUptime: TimeInterval) -> Bool {
        guard nowUptime.isFinite,
              hasEncodedFrameInCurrentConfig,
              pendingCrispRefresh,
              let motionAt = lastMotionUptime,
              nowUptime >= motionAt,
              nowUptime - motionAt >= crispRefreshDelay else {
            return false
        }
        pendingCrispRefresh = false
        crispRefreshCount += 1
        lastAdmittedUptime = nowUptime
        return true
    }

    mutating func shouldEncodeFrame(
        hasDirtyRects: Bool,
        requiresKeyframe: Bool,
        nowUptime: TimeInterval
    ) -> Bool {
        evaluate(
            hasDirtyRects: hasDirtyRects,
            requiresKeyframe: requiresKeyframe,
            nowUptime: nowUptime
        ).shouldEncode
    }
}

enum SettledCrispRefreshEncoderPolicy {
    /// Tighter maximum QP cap applied for the single settled static-desktop refresh
    /// frame (`~180ms` after motion stops) so text and UI edges snap sharp without
    /// altering VBV frame-size limits or dropping subsequent frames.
    static let settledMaxAllowedFrameQP: Int = 20
    static let defaultMaxAllowedFrameQPCeiling: Int = 51
    static let settledSpatialQualityHint: Float = 0.90

    static func withCrispRefreshHints<T>(
        encoder: VTCompressionSession,
        enabled: Bool,
        restoreSpeedOverQuality: Bool,
        restoreBitrate: Int,
        restoreVBVLimits: [NSNumber],
        body: () -> T
    ) -> T {
        guard enabled else { return body() }
        var originalMaxQPRef: Unmanaged<CFTypeRef>?
        let hadOriginalMaxQP = VTSessionCopyProperty(
            encoder,
            key: kVTCompressionPropertyKey_MaxAllowedFrameQP,
            allocator: nil,
            valueOut: &originalMaxQPRef
        ) == noErr
        let originalMaxQP = originalMaxQPRef?.takeRetainedValue()
        // Before MaxAllowedFrameQP is explicitly set, VideoToolbox returns negative
        // sentinels (-13 or -1) from VTSessionCopyProperty, which VTSessionSetProperty
        // rejects with kVTPropertyErr (-12900). Restore a valid 1...51 ceiling.
        let restoreMaxQP: Int = {
            if hadOriginalMaxQP,
               let number = originalMaxQP as? NSNumber,
               (1...51).contains(number.intValue) {
                return number.intValue
            }
            return defaultMaxAllowedFrameQPCeiling
        }()

        VTSessionSetProperty(
            encoder,
            key: kVTCompressionPropertyKey_PrioritizeEncodingSpeedOverQuality,
            value: kCFBooleanFalse
        )
        VTSessionSetProperty(
            encoder,
            key: kVTCompressionPropertyKey_MaxAllowedFrameQP,
            value: settledMaxAllowedFrameQP as CFNumber
        )
        let qualityStatus = VTSessionSetProperty(
            encoder,
            key: kVTCompressionPropertyKey_Quality,
            value: settledSpatialQualityHint as CFNumber
        )
        defer {
            VTSessionSetProperty(
                encoder,
                key: kVTCompressionPropertyKey_MaxAllowedFrameQP,
                value: restoreMaxQP as CFNumber
            )
            VTSessionSetProperty(
                encoder,
                key: kVTCompressionPropertyKey_PrioritizeEncodingSpeedOverQuality,
                value: restoreSpeedOverQuality ? kCFBooleanTrue : kCFBooleanFalse
            )
            if qualityStatus == noErr, restoreBitrate > 0 {
                VTSessionSetProperty(
                    encoder,
                    key: kVTCompressionPropertyKey_AverageBitRate,
                    value: restoreBitrate as CFNumber
                )
                VTSessionSetProperty(
                    encoder,
                    key: kVTCompressionPropertyKey_DataRateLimits,
                    value: restoreVBVLimits as CFArray
                )
            }
        }
        return body()
    }
}

enum CaptureTimestampPolicy {
    static let maxCaptureLookbackMs: Double = 250.0

    /// Converts a Mach absolute display timestamp (`SCStreamFrameInfo.displayTime`)
    /// into the wall-clock millisecond domain (`Date().timeIntervalSince1970 * 1000`)
    /// used by `VideoFrameWirePayload` (`capturedAtMs` and `sndMs`), preventing
    /// host-clock vs. wall-clock domain mismatch while preserving accurate
    /// WindowServer-to-encode capture age.
    static func captureTimestampMs(
        from displayTimeAttachment: Any?,
        nowWallMs: Double = Date().timeIntervalSince1970 * 1000,
        nowHostSeconds: Double = CMTimeGetSeconds(CMClockGetTime(CMClockGetHostTimeClock()))
    ) -> Int64 {
        let displayHostSeconds: Double?
        if let ticks = (displayTimeAttachment as? NSNumber)?.uint64Value, ticks > 0 {
            let cmTime = CMClockMakeHostTimeFromSystemUnits(ticks)
            let seconds = CMTimeGetSeconds(cmTime)
            displayHostSeconds = seconds.isFinite && seconds > 0 ? seconds : nil
        } else {
            displayHostSeconds = nil
        }
        return wallClockCaptureMs(
            nowWallMs: nowWallMs,
            displayTimeHostSeconds: displayHostSeconds,
            nowHostSeconds: nowHostSeconds
        )
    }

    static func wallClockCaptureMs(
        nowWallMs: Double,
        displayTimeHostSeconds: Double?,
        nowHostSeconds: Double,
        maxLookbackMs: Double = maxCaptureLookbackMs
    ) -> Int64 {
        guard nowWallMs.isFinite else { return 0 }
        guard let displayTimeHostSeconds,
              displayTimeHostSeconds.isFinite,
              nowHostSeconds.isFinite else {
            return Int64(nowWallMs.rounded())
        }
        let elapsedMs = (nowHostSeconds - displayTimeHostSeconds) * 1000.0
        guard elapsedMs.isFinite, elapsedMs >= 0 else {
            return Int64(nowWallMs.rounded())
        }
        let clampedLookbackMs = min(elapsedMs, max(0, maxLookbackMs))
        return Int64((nowWallMs - clampedLookbackMs).rounded())
    }
}

import CoreGraphics
import CoreMedia
import Foundation

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
/// 4. Periodic static keepalive refresh (`maxStaticRefreshInterval`).
struct CaptureStaticFrameGate: Sendable {
    let settlingTailFrames: Int
    let maxStaticRefreshInterval: TimeInterval

    private(set) var hasEncodedFrameInCurrentConfig = false
    private(set) var remainingSettlingFrames = 0
    private(set) var lastAdmittedUptime: TimeInterval?
    private(set) var skippedStaticFrames = 0

    init(
        settlingTailFrames: Int = 1,
        maxStaticRefreshInterval: TimeInterval = 0.5
    ) {
        self.settlingTailFrames = max(0, settlingTailFrames)
        self.maxStaticRefreshInterval = max(0.05, maxStaticRefreshInterval)
    }

    mutating func resetForNewConfiguration() {
        hasEncodedFrameInCurrentConfig = false
        remainingSettlingFrames = settlingTailFrames
        lastAdmittedUptime = nil
    }

    mutating func markFrameEncoded() {
        hasEncodedFrameInCurrentConfig = true
    }

    mutating func shouldEncodeFrame(
        hasDirtyRects: Bool,
        requiresKeyframe: Bool,
        nowUptime: TimeInterval
    ) -> Bool {
        guard nowUptime.isFinite else { return true }
        if !hasEncodedFrameInCurrentConfig || requiresKeyframe || hasDirtyRects {
            remainingSettlingFrames = settlingTailFrames
            lastAdmittedUptime = nowUptime
            return true
        }
        if remainingSettlingFrames > 0 {
            remainingSettlingFrames -= 1
            lastAdmittedUptime = nowUptime
            return true
        }
        if let last = lastAdmittedUptime,
           nowUptime >= last,
           nowUptime - last < maxStaticRefreshInterval {
            skippedStaticFrames += 1
            return true == false
        }
        lastAdmittedUptime = nowUptime
        return true
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

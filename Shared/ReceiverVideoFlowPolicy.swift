import Foundation

/// `isReadyForMoreMediaData == false` is occupancy feedback, not a decode
/// failure. AVQueuedSampleBufferRendering permits bounded real-time enqueueing
/// in this state. Preserve short reference chains; abandon sustained backlog.
struct ReceiverVideoBackpressurePolicy {
    enum Action { case enqueue, flushAndWait, wait }
    private var notReadySince: TimeInterval?
    private var additionalFrames = 0
    private var flushed = false

    mutating func action(isReady: Bool, now: TimeInterval) -> Action {
        if isReady {
            self = Self()
            return .enqueue
        }
        if flushed { return .wait }
        if notReadySince == nil { notReadySince = now }
        guard let notReadySince, additionalFrames < 2, now - notReadySince < 0.050 else {
            flushed = true
            return .flushAndWait
        }
        additionalFrames += 1
        return .enqueue
    }
}

/// Heartbeats prove the socket is alive, not that the sender produced video.
/// This deadline ends permanently after the first valid submitted frame.
struct ReceiverFirstVideoDeadline {
    private var startedAt: TimeInterval?
    mutating func begin(at now: TimeInterval) { startedAt = now }
    mutating func receivedFrame() { startedAt = nil }
    func expired(at now: TimeInterval) -> Bool {
        startedAt.map { now - $0 >= 15 } ?? false
    }
}

/// Tracks generation-scoped liveness monitor loops across start/stop/resume
/// transitions so backgrounding neither strands monitors permanently nor spawns
/// duplicate timer chains when foregrounded within a timer interval.
struct ReceiverMonitorSchedule {
    private(set) var generation: UInt64 = 0
    private(set) var active = false

    mutating func activateIfNeeded() -> UInt64? {
        guard !active else { return nil }
        generation &+= 1
        active = true
        return generation
    }

    mutating func deactivate() {
        guard active else { return }
        generation &+= 1
        active = false
    }

    func isCurrent(_ candidate: UInt64) -> Bool {
        active && generation == candidate
    }
}

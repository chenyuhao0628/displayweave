import Foundation
import CoreGraphics
import Network

struct CursorPosition: Equatable {
    var x: Double
    var y: Double
    var visible: Bool

    static func sample(displayID: CGDirectDisplayID) -> CursorPosition? {
        guard let point = CGEvent(source: nil)?.location else { return nil }
        let bounds = CGDisplayBounds(displayID)
        guard bounds.width > 0, bounds.height > 0 else { return nil }
        guard bounds.contains(point) else { return CursorPosition(x: 0, y: 0, visible: false) }
        return CursorPosition(x: (point.x - bounds.minX) / bounds.width,
                              y: (point.y - bounds.minY) / bounds.height, visible: true)
    }
}

/// Sampling must not wait behind a synchronous VideoToolbox submission. Keep
/// the existing authenticated framed connection and bound cursor writes when
/// that connection (or its callback queue) is busy.
final class CursorEcho: @unchecked Sendable {
    typealias Write = (Data, @escaping (Bool) -> Void) -> Void

    static func writer(on connection: NWConnection) -> Write {
        { data, complete in
            // Prioritize only messages still queued in Network.framework.
            // A complete framed message stays atomic; already-sent TCP bytes
            // cannot be overtaken. Video/configuration retain their ordering.
            let context = NWConnection.ContentContext(identifier: "cursor", priority: 1)
            connection.send(content: data, contentContext: context, isComplete: true,
                            completion: .contentProcessed { complete($0 == nil) })
        }
    }
    private let queue = DispatchQueue(label: "displayweave.cursor", qos: .userInteractive)
    private let relay = LatestValueRelay<CursorPosition>()
    private var timer: DispatchSourceTimer?
    private var write: Write?
    private var lastPosition: CursorPosition?
    private var sequence: UInt64 = 0
    private var statsStart: TimeInterval = 0
    private var lastPoll: TimeInterval = 0
    private var maxPollGapMs: Double = 0
    private var maxCompletionMs: Double = 0

    func start(sample: @escaping () -> CursorPosition?, write: @escaping Write,
               log: ((String) -> Void)? = nil) {
        queue.sync {
            resetOnQueue()
            self.write = write
            statsStart = ProcessInfo.processInfo.systemUptime
            lastPoll = statsStart
            let timer = DispatchSource.makeTimerSource(queue: queue)
            timer.schedule(deadline: .now(), repeating: .milliseconds(8), leeway: .milliseconds(1))
            timer.setEventHandler { [weak self] in
                guard let self else { return }
                let now = ProcessInfo.processInfo.systemUptime
                self.maxPollGapMs = max(self.maxPollGapMs, (now - self.lastPoll) * 1_000)
                self.lastPoll = now
                if let position = sample(), position != self.lastPosition {
                    self.lastPosition = position
                    if let token = self.relay.offer(position) { self.submit(token) }
                }
                if now - self.statsStart >= 2 {
                    let stats = self.relay.takeMetrics()
                    if stats.offered > 0 || stats.completed > 0 {
                        log?("CURSOR-SEND changed=\(stats.offered) coalesced=\(stats.coalesced) completed=\(stats.completed) maxSampleGapMs=\(Int(self.maxPollGapMs)) maxCompletionMs=\(Int(self.maxCompletionMs))")
                    }
                    self.statsStart = now
                    self.maxPollGapMs = 0
                    self.maxCompletionMs = 0
                }
            }
            timer.resume()
            self.timer = timer
        }
    }

    func stop() { queue.sync { resetOnQueue() } }

    deinit { timer?.cancel() }

    private func resetOnQueue() {
        timer?.cancel(); timer = nil
        relay.reset()
        write = nil
        lastPosition = nil
        maxCompletionMs = 0
        maxPollGapMs = 0
    }

    private func submit(_ token: LatestValueRelay<CursorPosition>.Token) {
        guard let position = relay.take(token), let write else { return }
        sequence &+= 1
        // Preserve precision instead of the old 0.0004 deadband (~1.6 pixels at 4K).
        let object: [String: Any] = ["type": "cursor", "x": position.x,
            "y": position.y, "v": position.visible ? 1 : 0, "s": sequence]
        guard let data = try? JSONSerialization.data(withJSONObject: object) else {
            resetOnQueue(); return
        }
        let started = ProcessInfo.processInfo.systemUptime
        write(ReceiverFrameDecoder.frame(data)) { [weak self] success in
            guard let self else { return }
            self.queue.async {
                guard self.relay.isCurrent(token) else { return }
                self.maxCompletionMs = max(self.maxCompletionMs,
                    (ProcessInfo.processInfo.systemUptime - started) * 1_000)
                guard success else { self.resetOnQueue(); return }
                if let next = self.relay.complete(token) { self.submit(next) }
            }
        }
    }
}

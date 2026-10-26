import Foundation
import VideoToolbox

/// Retained, read-only frame input crossing to the serial encoder owner.
/// The session is only operated on through EncoderWorkQueue; capture pixels
/// are never mutated by the sender. CoreVideo/VideoToolbox lack Sendable here.
struct EncoderFrameSubmission: @unchecked Sendable {
    let encoder: VTCompressionSession
    let pixels: CVPixelBuffer
    let properties: CFDictionary?
}

/// Some VideoToolbox drivers block inside EncodeFrame. Keep that work off the
/// capture/control queue, with at most two retained submissions across sessions.
/// Session creation, property changes and retirement use the same serial owner.
final class EncoderWorkQueue: @unchecked Sendable {
    private let queue = DispatchQueue(label: "sender.encoder", qos: .userInteractive)
    private let lock = NSLock()
    private var submissions = 0

    func submit(limit: Int, _ work: @escaping @Sendable () -> Void) -> Bool {
        lock.lock()
        guard submissions < min(2, max(1, limit)) else { lock.unlock(); return false }
        submissions += 1
        lock.unlock()
        queue.async {
            defer {
                self.lock.lock(); self.submissions -= 1; self.lock.unlock()
            }
            work()
        }
        return true
    }

    /// Never call from a submission. Callbacks must dispatch asynchronously to
    /// the state owner, so retirement can drain submissions without a cycle.
    func perform<T>(_ work: () throws -> T) rethrows -> T {
        try queue.sync(execute: work)
    }
}

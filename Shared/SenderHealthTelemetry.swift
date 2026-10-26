import Foundation

/// Shared current/legacy ping contract. Missing fields keep the previous sample;
/// an explicit zero clears it. Counts cannot be negative.
struct SenderHealthTelemetry {
    let droppedFrames: Int?
    let queueDepth: Int?

    init(_ object: [String: Any]) {
        func count(_ current: String, _ legacy: String) -> Int? {
            guard let value = object[current] as? Int ?? object[legacy] as? Int,
                  value >= 0 else { return nil }
            return value
        }
        droppedFrames = count("droppedFramesMac", "drops")
        queueDepth = count("queueDepthMac", "pending")
    }
}

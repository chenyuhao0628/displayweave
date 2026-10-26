import Foundation

@main enum EncoderLoadControllerSelfTest {
    static func main() {
        let original = EncoderLoadController.Configuration(width: 4096, height: 2304, fps: 60)
        func sample(_ time: Double, captures: Int = 88, outputs: Int = 62, drops: Int = 28,
                    ms: Double = 25, pending: Int = 0) -> EncoderLoadController.Sample {
            .init(now: time, seconds: 2, captures: captures, outputs: outputs, encoderDrops: drops,
                  submissions: outputs, submissionMs: ms, pendingSends: pending, sendCompletionMs: 0.2)
        }
        var detail = EncoderLoadController(configuration: original, priority: .resolution)
        precondition(detail.evaluate(sample(2)) == nil)
        precondition(detail.evaluate(sample(4)) == nil)
        let paced = detail.evaluate(sample(6))!
        precondition(paced.configuration == .init(width: 4096, height: 2304, fps: 30))
        var motion = EncoderLoadController(configuration: original, priority: .frameRate)
        for time in [2.0, 4] { precondition(motion.evaluate(sample(time)) == nil) }
        let scaled = motion.evaluate(sample(6))!
        precondition(scaled.configuration.width == 3480 && scaled.configuration.height == 1958)
        precondition(scaled.configuration.fps == 60)
        // Short bursts, a static desktop, network congestion and stale/invalid
        // metrics must never masquerade as sustained encoder overload.
        var idle = EncoderLoadController(configuration: original, priority: .frameRate)
        for time in stride(from: 2.0, through: 120, by: 2) {
            precondition(idle.evaluate(sample(time, captures: 2, outputs: 2, drops: 0)) == nil)
            precondition(idle.evaluate(sample(time, captures: 30, outputs: 30, drops: 0)) == nil,
                         "naturally sparse animation with slow encodes is not overload")
            precondition(idle.evaluate(sample(time, pending: 1)) == nil)
        }
        precondition(idle.current == original)
        precondition(idle.evaluate(sample(.nan)) == nil)
        for time in [130.0, 160, 190] { precondition(idle.evaluate(sample(time)) == nil) }
        // Sustained healthy motion restores quality; idle time alone cannot.
        for time in stride(from: 8.0, through: 34, by: 2) {
            precondition(motion.evaluate(sample(time, captures: 120, outputs: 120, drops: 0, ms: 7)) == nil)
        }
        precondition(motion.evaluate(sample(36, captures: 120, outputs: 120, drops: 0, ms: 7))?.configuration == original)
        var bounded = EncoderLoadController(configuration: original, priority: .frameRate)
        for time in stride(from: 2.0, through: 300, by: 2) {
            _ = bounded.evaluate(sample(time, outputs: 20))
        }
        precondition(bounded.current.width >= 2048 && bounded.current.height >= 1152 && bounded.current.fps >= 30)
        precondition(bounded.current.width % 2 == 0 && bounded.current.height % 2 == 0)
        let fresh = EncoderLoadController(configuration: original, priority: .frameRate)
        precondition(fresh.current == original, "a new session must not inherit an old overload")
        print("Measured encoder adaptation, idle/network exclusions, recovery and bounds PASS")
    }
}

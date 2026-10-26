import Foundation

/// Measured Mac encoder load, independent of desktop points and network bitrate.
/// Only active capture windows can change the stream. Idle desktops are healthy.
struct EncoderLoadController {
    struct Configuration: Equatable {
        let width: Int
        let height: Int
        let fps: Int
    }
    struct Sample {
        let now: TimeInterval
        let seconds: Double
        let captures: Int
        let outputs: Int
        let encoderDrops: Int
        let submissions: Int
        let submissionMs: Double
        let pendingSends: Int
        let sendCompletionMs: Double
    }
    struct Decision {
        let configuration: Configuration
        let recovering: Bool
    }

    let original: Configuration
    let priority: StreamPriority
    private(set) var current: Configuration
    private var pressureWindows = 0
    private var healthyWindows = 0
    private var lastActive: TimeInterval?
    private var lastChange = -Double.infinity
    private var recoveryAfter = Double.infinity
    private var recoveryDelay: Double = 30
    private var lastRecovery: TimeInterval?

    init(configuration: Configuration, priority: StreamPriority) {
        original = configuration
        current = configuration
        self.priority = priority
    }

    mutating func evaluate(_ sample: Sample) -> Decision? {
        guard sample.now.isFinite, sample.seconds.isFinite, sample.seconds >= 0.5,
              sample.seconds <= 5, sample.submissionMs.isFinite, sample.submissionMs >= 0,
              sample.submissions >= 10,
              Double(sample.captures) / sample.seconds >= max(12, Double(current.fps) * 0.25),
              sample.pendingSends == 0, sample.sendCompletionMs.isFinite,
              sample.sendCompletionMs >= 0, sample.sendCompletionMs < 20 else {
            healthyWindows = 0
            return nil
        }
        if let lastActive, sample.now - lastActive > 20 || sample.now < lastActive {
            pressureWindows = 0; healthyWindows = 0
        }
        lastActive = sample.now
        let interval = 1000 / Double(max(1, current.fps))
        let outputFps = Double(sample.outputs) / sample.seconds
        let captureFps = Double(sample.captures) / sample.seconds
        let dropFraction = Double(sample.encoderDrops) / Double(max(1, sample.captures))
        let overloaded = outputFps < Double(current.fps) * 0.85
            && (dropFraction >= 0.12 || (captureFps >= Double(current.fps) * 0.9
                && sample.submissionMs > interval * 0.9))
        pressureWindows = overloaded ? pressureWindows + 1 : 0
        if overloaded {
            healthyWindows = 0
            guard pressureWindows >= 3, sample.now - lastChange >= 8,
                  let lower = lowerConfiguration(outputFps: outputFps) else { return nil }
            if let lastRecovery, sample.now - lastRecovery < 20 {
                recoveryDelay = min(300, recoveryDelay * 2)
            }
            recoveryAfter = sample.now + recoveryDelay
            return change(to: lower, now: sample.now, recovering: false)
        }

        guard current != original, sample.encoderDrops == 0,
              outputFps >= Double(current.fps) * 0.85,
              let higher = higherConfiguration() else { healthyWindows = 0; return nil }
        let pixelRatio = Double(higher.width * higher.height) / Double(current.width * current.height)
        let projectedLoad = sample.submissionMs * pixelRatio * Double(higher.fps) / 1000
        healthyWindows = projectedLoad < 0.75 ? healthyWindows + 1 : 0
        guard healthyWindows >= 5, sample.now >= recoveryAfter else { return nil }
        lastRecovery = sample.now
        recoveryAfter = sample.now + recoveryDelay
        return change(to: higher, now: sample.now, recovering: true)
    }

    private mutating func change(to configuration: Configuration, now: Double, recovering: Bool) -> Decision {
        current = configuration
        pressureWindows = 0; healthyWindows = 0; lastChange = now
        return Decision(configuration: configuration, recovering: recovering)
    }

    private var rasters: [(Int, Int)] {
        let minimumScale = min(1, max(0.5, 1280 / Double(max(original.width, original.height))))
        return [1.0, 0.85, 0.7, 0.5].map { factor in
            let scale = max(minimumScale, factor)
            return (max(2, Int(Double(original.width) * scale) & ~1),
                    max(2, Int(Double(original.height) * scale) & ~1))
        }
    }

    private func lowerConfiguration(outputFps: Double) -> Configuration? {
        if priority == .frameRate,
           let raster = rasters.first(where: { $0.0 * $0.1 < current.width * current.height }) {
            return Configuration(width: raster.0, height: raster.1, fps: current.fps)
        }
        let floor = min(30, original.fps)
        let fps = [120, 90, 60, 50, 40, 30].first {
            $0 < current.fps && $0 <= max(floor, Int(outputFps * 0.95))
        }
        guard let fps, fps >= floor else { return nil }
        return Configuration(width: current.width, height: current.height, fps: fps)
    }

    private func higherConfiguration() -> Configuration? {
        if current.fps < original.fps {
            let fps = [30, 40, 50, 60, 90, 120].first { $0 > current.fps && $0 <= original.fps } ?? original.fps
            return Configuration(width: current.width, height: current.height, fps: fps)
        }
        guard let raster = rasters.reversed().first(where: { $0.0 * $0.1 > current.width * current.height }) else { return nil }
        return Configuration(width: raster.0, height: raster.1, fps: current.fps)
    }
}

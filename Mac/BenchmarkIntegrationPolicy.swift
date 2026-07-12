import Foundation

enum BenchmarkControlPolicy {
    static func seconds(from duration: ContinuousClock.Duration) -> TimeInterval {
        let parts = duration.components
        return TimeInterval(parts.seconds) + TimeInterval(parts.attoseconds) / 1_000_000_000_000_000_000
    }

    static func receiverStats(from data: Data) throws -> ReceiverStats? {
        let stats = try JSONDecoder().decode(ReceiverStats.self, from: data)
        return stats.type == "stats" ? stats : nil
    }

    static func pongData(pingTimestamp: Double, macReceivedTimestamp: Double,
                         macSentTimestamp: Double) throws -> Data {
        try JSONSerialization.data(withJSONObject: [
            "type": "pong", "t": pingTimestamp,
            "mt": macSentTimestamp, // legacy receiver compatibility
            "mr": macReceivedTimestamp, "ms": macSentTimestamp
        ], options: [.sortedKeys])
    }
}

enum BenchmarkRecordingGate {
    static func shouldAppend(isRecorderActive: Bool, hasReceiverStats: Bool) -> Bool {
        isRecorderActive && hasReceiverStats
    }
}

enum BenchmarkPhase: String {
    case warmup, run, finished
}

enum BenchmarkScene: String, CaseIterable {
    case staticDesktop, textScroll, browserScroll, testPattern120, rapidWindowDrag

    var label: String {
        switch self {
        case .staticDesktop: return "Static Desktop"
        case .textScroll: return "Text Scroll"
        case .browserScroll: return "Browser Scroll"
        case .testPattern120: return "120Hz Test Pattern"
        case .rapidWindowDrag: return "Rapid Window Drag"
        }
    }
}

enum BenchmarkDuration: Int, CaseIterable {
    case standard = 180, extended = 300, optional = 600
    var label: String { "\(rawValue / 60) min" }
}

struct BenchmarkLaunchOptions: Equatable {
    var autoStart: Bool
    var scene: BenchmarkScene
    var duration: BenchmarkDuration

    static func parse(_ arguments: [String]) -> BenchmarkLaunchOptions {
        func value(after flag: String) -> String? {
            guard let index = arguments.firstIndex(of: flag),
                  arguments.indices.contains(index + 1) else { return nil }
            return arguments[index + 1]
        }
        return BenchmarkLaunchOptions(
            autoStart: arguments.contains("-benchmark-auto"),
            scene: value(after: "-benchmark-scene")
                .flatMap(BenchmarkScene.init(rawValue:)) ?? .staticDesktop,
            duration: value(after: "-benchmark-duration")
                .flatMap(Int.init).flatMap(BenchmarkDuration.init(rawValue:)) ?? .standard)
    }
}

struct BenchmarkPhasePolicy {
    var warmupSeconds: TimeInterval = 30
    var runSeconds: TimeInterval

    func phase(elapsedSeconds: TimeInterval) -> BenchmarkPhase {
        if elapsedSeconds < warmupSeconds { return .warmup }
        if elapsedSeconds < warmupSeconds + runSeconds { return .run }
        return .finished
    }
}

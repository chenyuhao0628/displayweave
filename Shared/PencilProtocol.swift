import Foundation

/// Explicit capability: protocol version alone never enables tablet input.
enum PencilProtocol {
    static let capability = "pencil-v1"
    static func supports(_ capabilities: [String]?) -> Bool {
        capabilities?.contains(capability) == true
    }
}

struct PencilSample {
    enum Phase: String { case down, move, up, cancel, hover }
    let phase: Phase
    let x: Double
    let y: Double
    let pressure: Double
    let azimuth: Double
    let altitude: Double

    init?(phase: Phase, x: Double, y: Double, pressure: Double, azimuth: Double, altitude: Double) {
        guard [x, y, pressure, azimuth, altitude].allSatisfy(\.isFinite),
              (0...1).contains(x), (0...1).contains(y), (0...1).contains(pressure),
              (-2 * Double.pi...2 * Double.pi).contains(azimuth), (0...Double.pi / 2).contains(altitude) else { return nil }
        self.phase = phase; self.x = x; self.y = y
        self.pressure = phase == .down || phase == .move ? pressure : 0
        self.azimuth = azimuth; self.altitude = altitude
    }

    init?(message: [String: Any]) {
        guard message["type"] as? String == "pencil",
              let phase = (message["phase"] as? String).flatMap(Phase.init(rawValue:)),
              let x = message["x"] as? Double, let y = message["y"] as? Double,
              let pressure = message["pressure"] as? Double,
              let azimuth = message["azimuth"] as? Double, let altitude = message["altitude"] as? Double else { return nil }
        self.init(phase: phase, x: x, y: y, pressure: pressure, azimuth: azimuth, altitude: altitude)
    }

    var message: [String: Any] {
        ["type": "pencil", "phase": phase.rawValue, "x": x, "y": y,
         "pressure": pressure, "azimuth": azimuth, "altitude": altitude]
    }
    var touchMessage: [String: Any] {
        let phase: String
        switch self.phase {
        case .down: phase = "began"
        case .move, .hover: phase = "moved"
        case .up: phase = "ended"
        case .cancel: phase = "cancelled"
        }
        return ["type": "touch", "phase": phase, "x": x, "y": y]
    }
    var tilt: (x: Double, y: Double) {
        // UIKit azimuth starts on +X and increases clockwise. AppKit tablet
        // tilt uses +X to the right and +Y down, in the same screen axes.
        let magnitude = (Double.pi / 2 - altitude) / (Double.pi / 2)
        return (cos(azimuth) * magnitude, sin(azimuth) * magnitude)
    }
}

/// Queue-owned. Lock the protocol for a whole contact if negotiation arrives late.
struct PencilInputForwarder {
    private var nativeStroke: Bool?
    private var last: PencilSample?

    mutating func messages(for sample: PencilSample, enabled: Bool) -> [[String: Any]] {
        var messages: [[String: Any]] = []
        switch sample.phase {
        case .down:
            if let nativeStroke, let last {
                let cancelled = PencilSample(phase: .cancel, x: last.x, y: last.y, pressure: 0,
                                             azimuth: last.azimuth, altitude: last.altitude)!
                messages.append(nativeStroke ? cancelled.message : cancelled.touchMessage)
            }
            nativeStroke = enabled
        case .move, .up, .cancel:
            guard nativeStroke != nil else { return [] }
        case .hover:
            guard nativeStroke == nil else { return [] }
        }
        messages.append((nativeStroke ?? enabled) ? sample.message : sample.touchMessage)
        last = sample
        if sample.phase == .up || sample.phase == .cancel { nativeStroke = nil }
        return messages
    }
}

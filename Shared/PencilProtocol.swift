import Foundation
import CoreFoundation

/// Explicit capability: protocol version alone never enables tablet input.
enum PencilProtocol {
    static let capability = "pencil-v1"
    static let extendedCapability = "pencil-v2"
    static func supports(_ capabilities: [String]?) -> Bool {
        capabilities?.contains(capability) == true
    }
}

enum PencilTool: String, CaseIterable { case pen, eraser }

struct PencilSample {
    enum Phase: String { case down, move, up, cancel, hover }
    let phase: Phase
    let x: Double
    let y: Double
    let pressure: Double
    let azimuth: Double
    let altitude: Double
    let roll: Double
    let tool: PencilTool

    init?(phase: Phase, x: Double, y: Double, pressure: Double, azimuth: Double, altitude: Double,
          roll: Double = 0, tool: PencilTool = .pen) {
        guard [x, y, pressure, azimuth, altitude, roll].allSatisfy(\.isFinite),
              (0...1).contains(x), (0...1).contains(y), (0...1).contains(pressure),
              (-2 * Double.pi...2 * Double.pi).contains(azimuth), (0...Double.pi / 2).contains(altitude),
              (-2 * Double.pi...2 * Double.pi).contains(roll) else { return nil }
        self.phase = phase; self.x = x; self.y = y
        self.pressure = phase == .down || phase == .move ? pressure : 0
        self.azimuth = azimuth; self.altitude = altitude
        self.roll = roll; self.tool = tool
    }

    init?(message: [String: Any]) {
        guard let type = message["type"] as? String, ["pencil", "pencil2"].contains(type),
              let phase = (message["phase"] as? String).flatMap(Phase.init(rawValue:)),
              let x = Self.number(message["x"]), let y = Self.number(message["y"]),
              let pressure = Self.number(message["pressure"]),
              let azimuth = Self.number(message["azimuth"]), let altitude = Self.number(message["altitude"]) else { return nil }
        let extended = type == "pencil2"
        guard let roll = Self.number(extended ? message["roll"] : 0),
              let tool = (extended ? message["tool"] as? String : "pen").flatMap(PencilTool.init(rawValue:)) else { return nil }
        self.init(phase: phase, x: x, y: y, pressure: pressure, azimuth: azimuth, altitude: altitude, roll: roll, tool: tool)
    }

    private static func number(_ value: Any?) -> Double? {
        guard let n = value as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID() else { return nil }
        return n.doubleValue
    }

    var cancelled: PencilSample {
        PencilSample(phase: .cancel, x: x, y: y, pressure: 0, azimuth: azimuth, altitude: altitude, roll: roll, tool: tool)!
    }
    var extendedMessage: [String: Any] {
        message.merging(["type": "pencil2", "roll": roll, "tool": tool.rawValue]) { _, new in new }
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
    private var extendedStroke = false
    private var last: PencilSample?

    mutating func messages(for sample: PencilSample, enabled: Bool, extended: Bool = false) -> [[String: Any]] {
        var messages: [[String: Any]] = []
        switch sample.phase {
        case .down:
            if let nativeStroke, let last {
                let cancelled = last.cancelled
                messages.append(nativeStroke ? (extendedStroke ? cancelled.extendedMessage : cancelled.message) : cancelled.touchMessage)
            }
            nativeStroke = enabled
            extendedStroke = enabled && extended
        case .move, .up, .cancel:
            guard nativeStroke != nil else { return [] }
        case .hover:
            guard nativeStroke == nil else { return [] }
        }
        let useExtended = nativeStroke != nil ? extendedStroke : (enabled && extended)
        messages.append((nativeStroke ?? enabled) ? (useExtended ? sample.extendedMessage : sample.message) : sample.touchMessage)
        last = sample
        if sample.phase == .up || sample.phase == .cancel { nativeStroke = nil }
        return messages
    }
}

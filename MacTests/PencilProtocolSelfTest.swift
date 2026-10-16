import Foundation

@main struct PencilProtocolSelfTest {
    static func sample(_ phase: PencilSample.Phase, _ pressure: Double = 0.5) -> PencilSample {
        PencilSample(phase: phase, x: 0.25, y: 0.75, pressure: pressure, azimuth: 0, altitude: .pi / 4)!
    }
    static func main() {
        for invalid in [Double.nan, .infinity, -.infinity, -0.1, 1.1] {
            precondition(PencilSample(phase: .down, x: 0, y: 0, pressure: invalid, azimuth: 0, altitude: 0) == nil)
        }
        precondition(PencilSample(phase: .move, x: .nan, y: 0, pressure: 0, azimuth: 0, altitude: 0) == nil)
        precondition(PencilSample(phase: .move, x: 0, y: 0, pressure: 0, azimuth: .infinity, altitude: 0) == nil)
        precondition(PencilSample(phase: .move, x: 0, y: 0, pressure: 0, azimuth: 0, altitude: 2) == nil)
        precondition(PencilSample(message: sample(.down).message)?.phase == .down)
        precondition(PencilProtocol.supports(["future", "pencil-v1"]))
        precondition(!PencilProtocol.supports(nil))
        // UIKit azimuth zero points right; AppKit's positive axes point right/down.
        for (angle, expectedX, expectedY) in [(0.0, 0.5, 0.0), (Double.pi / 2, 0.0, 0.5),
                                            (Double.pi, -0.5, 0.0), (-Double.pi / 2, 0.0, -0.5)] {
            let tilt = PencilSample(phase: .move, x: 0.5, y: 0.5, pressure: 1,
                                    azimuth: angle, altitude: .pi / 4)!.tilt
            precondition(abs(tilt.x - expectedX) < 0.0001 && abs(tilt.y - expectedY) < 0.0001,
                         "Pencil tilt axes do not match the screen direction")
        }
        let upright = PencilSample(phase: .hover, x: 0.5, y: 0.5, pressure: 0,
                                   azimuth: 1, altitude: .pi / 2)!.tilt
        precondition(abs(upright.x) < 0.0001 && abs(upright.y) < 0.0001)
        var forwarder = PencilInputForwarder()
        precondition(forwarder.messages(for: sample(.down), enabled: false).first?["type"] as? String == "touch")
        // A capability reply arriving mid-stroke cannot change the input protocol.
        precondition(forwarder.messages(for: sample(.move), enabled: true).first?["type"] as? String == "touch")
        precondition(forwarder.messages(for: sample(.up), enabled: true).first?["phase"] as? String == "ended")
        precondition(forwarder.messages(for: sample(.down), enabled: true).first?["type"] as? String == "pencil")
        precondition(forwarder.messages(for: sample(.cancel), enabled: false).first?["phase"] as? String == "cancel")
        precondition(forwarder.messages(for: sample(.move), enabled: true).isEmpty)
        print("Pencil validation, explicit negotiation and per-stroke legacy compatibility PASS")
    }
}

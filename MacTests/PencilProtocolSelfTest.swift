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

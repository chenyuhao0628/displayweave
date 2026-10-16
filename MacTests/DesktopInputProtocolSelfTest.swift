import Foundation
import CoreGraphics

@main enum DesktopInputProtocolSelfTest {
    static func main() throws {
        let session = UUID().uuidString
        func decode(_ fields: [String: Any]) -> DesktopInputEvent? {
            let base: [String: Any] = ["type": "desktopInput", "inputSession": session, "sequence": 1,
                                       "kind": "move", "x": 0.25, "y": 0.75, "modifiers": 0]
            let object = base.merging(fields) { _, new in new }
            guard JSONSerialization.isValidJSONObject(object), let data = try? JSONSerialization.data(withJSONObject: object) else { return nil }
            return DesktopInputEvent.decode(data)
        }
        precondition(decode([:]) != nil)
        precondition(decode(["sequence": 0]) == nil)
        precondition(decode(["sequence": true]) == nil)
        precondition(decode(["x": 1.01]) == nil)
        precondition(decode(["x": true]) == nil)
        precondition(decode(["modifiers": 32]) == nil)
        precondition(decode(["kind": "unknown"]) == nil)
        precondition(decode(["inputSession": "old"]) == nil)
        precondition(decode(["kind": "keyDown", "keyCode": 128]) == nil)
        precondition(decode(["kind": "keyDown", "keyCode": 0]) != nil)
        precondition(decode(["kind": "buttonDown", "button": 3, "clicks": 1]) == nil)
        precondition(decode(["kind": "scroll", "dx": 4097, "dy": 0]) == nil)
        precondition(DesktopInputProtocol.permits(encrypted: true, consent: true, accessibility: true, capabilities: ["mac-input-v1"]))
        precondition(!DesktopInputProtocol.permits(encrypted: false, consent: true, accessibility: true, capabilities: ["mac-input-v1"]))
        precondition(!DesktopInputProtocol.permits(encrypted: true, consent: false, accessibility: true, capabilities: ["mac-input-v1"]))
        precondition(!DesktopInputProtocol.permits(encrypted: true, consent: true, accessibility: false, capabilities: ["mac-input-v1"]))
        var gate = DesktopInputSequence()
        gate.begin(session)
        let first = decode([:])!
        precondition(gate.accept(first) && !gate.accept(first))
        gate.begin(UUID().uuidString)
        precondition(!gate.accept(decode(["sequence": 2])!))
        gate.begin(nil)
        precondition(!gate.accept(first))
        let bounds = CGRect(x: 0, y: 0, width: 1000, height: 1000)
        let video = CGSize(width: 1600, height: 900)
        precondition(DesktopInputGeometry.normalized(CGPoint(x: 500, y: 500), in: bounds, video: video) == CGPoint(x: 0.5, y: 0.5))
        precondition(DesktopInputGeometry.normalized(CGPoint(x: 500, y: 50), in: bounds, video: video) == nil)
        precondition(DesktopInputGeometry.normalized(CGPoint(x: 1500, y: 50), in: bounds, video: video, clamp: true) == CGPoint(x: 1, y: 1))
        precondition(DesktopInputGeometry.normalized(.zero, in: bounds, video: .zero) == nil)
        print("Desktop input wire bounds, secure consent gates, grant/sequence isolation and aspect-fit mapping PASS")
    }
}

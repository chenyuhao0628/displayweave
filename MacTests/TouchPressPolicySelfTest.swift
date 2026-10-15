import Foundation
import CoreGraphics

@main struct TouchPressPolicySelfTest {
    static func main() {
        var policy = TouchPressPolicy()
        let origin = CGPoint(x: 0.2, y: 0.3), end = CGPoint(x: 0.4, y: 0.5)
        policy.begin(at: origin, screenPoint: .zero)
        precondition(policy.suppress().isEmpty, "second finger must not create a click")
        precondition(policy.end(at: end).isEmpty, "remaining finger must not release an unsent down")
        policy.begin(at: origin, screenPoint: .zero)
        precondition(policy.end(at: end).map(\.phase) == ["began", "ended"])
        policy.begin(at: origin, screenPoint: .zero)
        precondition(policy.move(to: CGPoint(x: 5, y: 0)).isEmpty)
        let drag = policy.move(to: CGPoint(x: 11, y: 0))
        precondition(drag.count == 1 && drag[0].phase == "began" && drag[0].position == origin)
        precondition(policy.suppress().map(\.phase) == ["cancelled"])
        precondition(policy.end(at: end).isEmpty)
        policy.begin(at: origin, screenPoint: .zero)
        precondition(policy.commitHold().map(\.phase) == ["began"])
        precondition(policy.commitHold().isEmpty)
        precondition(policy.cancel().map(\.phase) == ["cancelled"])
        precondition(policy.commitHold().isEmpty, "cancelled timer resurrected a press")
        print("Touch press: tap, drag, hold, second-finger suppression and cancellation PASS")
    }
}

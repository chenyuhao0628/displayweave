import Foundation
import CoreGraphics

/// Deferred single-finger presses, adapted from OpenDisplay 04590ed (GPL-3.0).
/// A second finger can cancel before any mouse-down reaches the Mac.
struct TouchPressPolicy {
    struct Action {
        let phase: String
        let position: CGPoint
    }
    static let holdDelay = 0.12
    private var origin: CGPoint?
    private var screenOrigin = CGPoint.zero
    private var downSent = false

    mutating func begin(at position: CGPoint, screenPoint: CGPoint) {
        origin = position
        screenOrigin = screenPoint
        downSent = false
    }

    mutating func commitHold() -> [Action] {
        guard let origin, !downSent else { return [] }
        downSent = true
        return [Action(phase: "began", position: origin)]
    }

    mutating func move(to screenPoint: CGPoint) -> [Action] {
        guard hypot(screenPoint.x - screenOrigin.x, screenPoint.y - screenOrigin.y) > 10 else { return [] }
        return commitHold()
    }

    mutating func end(at position: CGPoint) -> [Action] {
        var actions = commitHold()
        if downSent { actions.append(Action(phase: "ended", position: position)) }
        origin = nil; downSent = false
        return actions
    }

    mutating func suppress() -> [Action] { cancel() }

    mutating func cancel() -> [Action] {
        let actions = downSent ? [Action(phase: "cancelled", position: origin ?? .zero)] : []
        origin = nil; downSent = false
        return actions
    }
}

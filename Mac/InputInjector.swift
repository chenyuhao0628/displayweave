import CoreGraphics
import AppKit

/// Turns normalized touch coordinates from the phone into mouse events on a
/// target display. Touch semantics: finger down = left button down, finger
/// move = drag, finger up = button up — i.e. the phone acts as a touchscreen.
final class InputInjector {

    private let displayID: CGDirectDisplayID
    private var isDown = false
    private var lastPoint = CGPoint.zero
    // A real event source (vs nil) plus clickState=1 below: menu tracking
    // treats sourceless/zero-click synthetic clicks as malformed — menus
    // open but their tracking session breaks, leaving zombie menu windows
    // composited on the display (visible in the stream, unclickable).
    private let source = CGEventSource(stateID: .hidSystemState)

    init(displayID: CGDirectDisplayID) {
        self.displayID = displayID
    }

    static func ensureAccessibilityPermission() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        let trusted = AXIsProcessTrustedWithOptions(options)
        if !trusted {
            Log.info("Accessibility permission missing — prompt requested")
        }
        return trusted
    }

    /// x/y are normalized [0,1] in video space (origin top-left).
    func handleTouch(phase: String, x: Double, y: Double) {
        guard let x = InputValidationPolicy.coordinate(x),
              let y = InputValidationPolicy.coordinate(y) else { return }
        let bounds = CGDisplayBounds(displayID)   // global CG coords, y-down
        let point = CGPoint(
            x: bounds.origin.x + x * bounds.width,
            y: bounds.origin.y + y * bounds.height
        )

        lastPoint = point
        let type: CGEventType
        switch phase {
        case "began":
            type = .leftMouseDown
            isDown = true
        case "moved":
            type = isDown ? .leftMouseDragged : .mouseMoved
        case "ended", "cancelled":
            guard isDown else { return }   // spurious up without a down
            type = .leftMouseUp
            isDown = false
        default:
            return
        }

        guard let event = CGEvent(mouseEventSource: source, mouseType: type,
                                  mouseCursorPosition: point, mouseButton: .left) else { return }
        event.setIntegerValueField(.mouseEventClickState, value: phase == "cancelled" ? 0 : 1)
        event.post(tap: .cghidEventTap)
    }

    /// Release an interrupted drag before changing capture targets or stopping.
    func cancelPress() {
        guard isDown else { return }
        isDown = false
        guard let event = CGEvent(mouseEventSource: source, mouseType: .leftMouseUp,
                                  mouseCursorPosition: lastPoint, mouseButton: .left) else { return }
        event.setIntegerValueField(.mouseEventClickState, value: 0)
        event.post(tap: .cghidEventTap)
    }

    /// dx/dy in display pixels, natural-scrolling sign from the phone.
    /// Scroll events take points, so convert via the display's pixel scale.
    func handleScroll(dx: Double, dy: Double) {
        let bounds = CGDisplayBounds(displayID)
        let scale = bounds.width > 0 ? Double(CGDisplayPixelsWide(displayID)) / bounds.width : 2
        guard let wheelY = InputValidationPolicy.scroll(dy, scale: scale),
              let wheelX = InputValidationPolicy.scroll(dx, scale: scale) else { return }
        guard let event = CGEvent(scrollWheelEvent2Source: source, units: .pixel,
                                  wheelCount: 2,
                                  wheel1: wheelY,
                                  wheel2: wheelX,
                                  wheel3: 0) else { return }
        event.post(tap: .cghidEventTap)
    }
}

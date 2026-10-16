// Tablet fields adapted from peetzweg/opendisplay da9f369 (GPL-3.0).
import CoreGraphics
import AppKit

/// Turns normalized touch coordinates from the phone into mouse events on a
/// target display. Touch semantics: finger down = left button down, finger
/// move = drag, finger up = button up — i.e. the phone acts as a touchscreen.
final class InputInjector {

    private let displayID: CGDirectDisplayID
    private var isDown = false
    private var penDown = false
    private var inRange = false
    private let boundsProvider: () -> CGRect
    private let eventSink: ((CGEvent) -> Void)?
    private let tabletDeviceID: Int64 = 424242
    private var lastPoint = CGPoint.zero
    // A real event source (vs nil) plus clickState=1 below: menu tracking
    // treats sourceless/zero-click synthetic clicks as malformed — menus
    // open but their tracking session breaks, leaving zombie menu windows
    // composited on the display (visible in the stream, unclickable).
    private let source = CGEventSource(stateID: .hidSystemState)

    init(displayID: CGDirectDisplayID, boundsProvider: (() -> CGRect)? = nil,
         eventSink: ((CGEvent) -> Void)? = nil) {
        self.displayID = displayID
        self.boundsProvider = boundsProvider ?? { CGDisplayBounds(displayID) }
        self.eventSink = eventSink
    }

    private var canPost: Bool { eventSink != nil || AXIsProcessTrusted() }
    private func post(_ event: CGEvent) {
        if let eventSink { eventSink(event) }
        else if AXIsProcessTrusted() { event.post(tap: .cghidEventTap) }
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
        guard canPost, !penDown, let x = InputValidationPolicy.coordinate(x),
              let y = InputValidationPolicy.coordinate(y) else { return }
        let bounds = boundsProvider()   // global CG coords, y-down
        let point = CGPoint(
            x: bounds.origin.x + x * bounds.width,
            y: bounds.origin.y + y * bounds.height
        )

        lastPoint = point
        let type: CGEventType
        switch phase {
        case "began":
            cancelFingerPress()
            setProximity(false, at: point)
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
        post(event)
    }

    /// Release an interrupted drag before changing capture targets or stopping.
    func cancelPress() {
        cancelFingerPress()
        if penDown { postTablet(.leftMouseUp, at: lastPoint, pressure: 0, tilt: (0, 0), cancelled: true) }
        penDown = false
        setProximity(false, at: lastPoint)
    }

    private func cancelFingerPress() {
        guard isDown else { return }
        isDown = false
        guard let event = CGEvent(mouseEventSource: source, mouseType: .leftMouseUp,
                                  mouseCursorPosition: lastPoint, mouseButton: .left) else { return }
        event.setIntegerValueField(.mouseEventClickState, value: 0)
        post(event)
    }

    /// dx/dy in display pixels, natural-scrolling sign from the phone.
    /// Scroll events take points, so convert via the display's pixel scale.
    func handleScroll(dx: Double, dy: Double) {
        guard canPost, !penDown else { return }
        let bounds = boundsProvider()
        let scale = bounds.width > 0 ? Double(CGDisplayPixelsWide(displayID)) / bounds.width : 2
        guard let wheelY = InputValidationPolicy.scroll(dy, scale: scale),
              let wheelX = InputValidationPolicy.scroll(dx, scale: scale) else { return }
        guard let event = CGEvent(scrollWheelEvent2Source: source, units: .pixel,
                                  wheelCount: 2,
                                  wheel1: wheelY,
                                  wheel2: wheelX,
                                  wheel3: 0) else { return }
        post(event)
    }

    func handlePencil(_ sample: PencilSample) {
        guard canPost else { return }
        let bounds = boundsProvider()
        let point = CGPoint(x: bounds.minX + sample.x * bounds.width, y: bounds.minY + sample.y * bounds.height)
        switch sample.phase {
        case .down:
            cancelFingerPress()
            if penDown { postTablet(.leftMouseUp, at: lastPoint, pressure: 0, tilt: (0, 0), cancelled: true) }
            setProximity(true, at: point)
            penDown = true
            postTablet(.leftMouseDown, at: point, pressure: sample.pressure, tilt: sample.tilt)
        case .move:
            guard penDown else { return }
            postTablet(.leftMouseDragged, at: point, pressure: sample.pressure, tilt: sample.tilt)
        case .up, .cancel:
            if penDown {
                postTablet(.leftMouseUp, at: point, pressure: 0, tilt: sample.tilt, cancelled: sample.phase == .cancel)
            }
            penDown = false
            setProximity(false, at: point)
        case .hover:
            guard !penDown, !isDown else { return }
            setProximity(true, at: point)
            postTablet(.mouseMoved, at: point, pressure: 0, tilt: sample.tilt)
        }
        lastPoint = point
    }

    func handleProximity(entering: Bool, x: Double, y: Double) {
        guard canPost, x.isFinite, y.isFinite, (0...1).contains(x), (0...1).contains(y) else { return }
        let bounds = boundsProvider()
        let point = CGPoint(x: bounds.minX + x * bounds.width, y: bounds.minY + y * bounds.height)
        if !entering, penDown {
            postTablet(.leftMouseUp, at: point, pressure: 0, tilt: (0, 0), cancelled: true)
            penDown = false
        }
        setProximity(entering, at: point)
        lastPoint = point
    }

    private func setProximity(_ entering: Bool, at point: CGPoint) {
        guard entering != inRange else { return }
        inRange = entering
        guard let event = CGEvent(source: source) else { return }
        event.type = .tabletProximity
        event.location = point
        event.setIntegerValueField(.tabletProximityEventVendorID, value: 0x0D15)
        event.setIntegerValueField(.tabletProximityEventTabletID, value: 0x0101)
        event.setIntegerValueField(.tabletProximityEventPointerID, value: 0x0D02)
        event.setIntegerValueField(.tabletProximityEventDeviceID, value: tabletDeviceID)
        event.setIntegerValueField(.tabletProximityEventSystemTabletID, value: 0)
        event.setIntegerValueField(.tabletProximityEventPointerType, value: 1)
        event.setIntegerValueField(.tabletProximityEventVendorPointerType, value: 0x0802)
        // IOLLEvent.h: device ID, X/Y, buttons, tilt X/Y, pressure. No rotation.
        event.setIntegerValueField(.tabletProximityEventCapabilityMask, value: 0x05C7)
        event.setIntegerValueField(.tabletProximityEventEnterProximity, value: entering ? 1 : 0)
        event.flags = .maskNonCoalesced
        post(event)
    }

    private func postTablet(_ type: CGEventType, at point: CGPoint, pressure: Double,
                            tilt: (x: Double, y: Double), cancelled: Bool = false) {
        guard let event = CGEvent(mouseEventSource: source, mouseType: type,
                                  mouseCursorPosition: point, mouseButton: .left) else { return }
        event.setIntegerValueField(.mouseEventSubtype, value: Int64(CGEventMouseSubtype.tabletPoint.rawValue))
        event.setIntegerValueField(.mouseEventClickState, value: cancelled ? 0 : 1)
        event.setIntegerValueField(.tabletEventDeviceID, value: tabletDeviceID)
        event.setIntegerValueField(.tabletEventPointButtons, value: type == .leftMouseDown || type == .leftMouseDragged ? 1 : 0)
        event.setDoubleValueField(.mouseEventPressure, value: pressure)
        event.setIntegerValueField(.tabletEventPointPressure, value: Int64((pressure * 65535).rounded()))
        event.setDoubleValueField(.tabletEventTiltX, value: tilt.x)
        event.setDoubleValueField(.tabletEventTiltY, value: tilt.y)
        event.setDoubleValueField(.tabletEventRotation, value: 0)
        event.flags = .maskNonCoalesced
        post(event)
    }

}

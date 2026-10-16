import AppKit

/// Queue-owned input state. Tests supply a sink; they never post desktop events.
final class DesktopInputInjector {
    private let bounds: () -> CGRect
    private let sink: (CGEvent) -> Void
    private let source = CGEventSource(stateID: .privateState)
    private(set) var keys = Set<UInt16>()
    private(set) var buttons = Set<Int>()
    private(set) var modifiers = 0
    private var point = CGPoint.zero
    private static let modifierKeys: [CGKeyCode] = [56, 59, 58, 55, 57]
    private static let flags: [CGEventFlags] = [.maskShift, .maskControl, .maskAlternate, .maskCommand, .maskAlphaShift]

    init(displayID: CGDirectDisplayID, bounds: (() -> CGRect)? = nil, sink: ((CGEvent) -> Void)? = nil) {
        self.bounds = bounds ?? { CGDisplayBounds(displayID) }
        self.sink = sink ?? { $0.post(tap: .cghidEventTap) }
    }

    @discardableResult func handle(_ event: DesktopInputEvent) -> Bool {
        if event.kind == .releaseAll { cancel(); return true }
        if event.kind == .keyDown && !keys.contains(event.keyCode) && keys.count >= 16 { cancel(); return false }
        setModifiers(event.modifiers)
        switch event.kind {
        case .move, .buttonDown, .buttonUp, .scroll:
            let rect = bounds()
            guard rect.width > 0, rect.height > 0 else { cancel(); return false }
            // Stay inside the display at normalized 1 instead of hitting its neighbour.
            point = CGPoint(x: rect.minX + event.x * max(0, rect.width - 1),
                            y: rect.minY + event.y * max(0, rect.height - 1))
            if event.kind == .scroll {
                if let e = CGEvent(scrollWheelEvent2Source: source, units: .pixel, wheelCount: 2,
                                   wheel1: Int32(event.dy.rounded()), wheel2: Int32(event.dx.rounded()), wheel3: 0) {
                    e.location = point; post(e)
                }
            } else if event.kind == .buttonDown {
                guard buttons.insert(event.button).inserted else { return true }
                mouse(button: event.button, down: true, clicks: event.clicks)
            } else if event.kind == .buttonUp {
                guard buttons.remove(event.button) != nil else { return true }
                mouse(button: event.button, down: false, clicks: event.clicks)
            } else {
                let held = buttons.sorted().first
                let type: CGEventType = held == 0 ? .leftMouseDragged : held == 1 ? .rightMouseDragged : held == 2 ? .otherMouseDragged : .mouseMoved
                if let e = CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: point,
                                   mouseButton: CGMouseButton(rawValue: UInt32(held ?? 0))!) { post(e) }
            }
        case .keyDown:
            let held = keys.contains(event.keyCode)
            guard !event.repeating || held else { return true }
            guard !held || event.repeating else { return true }
            keys.insert(event.keyCode)
            key(event.keyCode, down: true, repeating: held)
        case .keyUp:
            if keys.remove(event.keyCode) != nil { key(event.keyCode, down: false) }
        case .modifiers: break
        case .releaseAll: break
        }
        return true
    }

    func cancel() {
        // Release regular keys while their chord modifiers still apply.
        for code in keys.sorted() { key(code, down: false) }
        keys.removeAll()
        for button in buttons.sorted() { mouse(button: button, down: false, clicks: 0) }
        buttons.removeAll()
        setModifiers(0)
    }

    private func post(_ event: CGEvent) {
        event.flags = Self.flags.enumerated().reduce(CGEventFlags()) { result, item in
            modifiers & (1 << item.offset) != 0 ? result.union(item.element) : result
        }
        sink(event)
    }
    private func key(_ code: UInt16, down: Bool, repeating: Bool = false) {
        guard let e = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: down) else { return }
        e.setIntegerValueField(.keyboardEventAutorepeat, value: repeating ? 1 : 0)
        post(e)
    }
    private func mouse(button: Int, down: Bool, clicks: Int) {
        let type: CGEventType = button == 0 ? (down ? .leftMouseDown : .leftMouseUp)
            : button == 1 ? (down ? .rightMouseDown : .rightMouseUp) : (down ? .otherMouseDown : .otherMouseUp)
        guard let e = CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: point,
                              mouseButton: CGMouseButton(rawValue: UInt32(button))!) else { return }
        e.setIntegerValueField(.mouseEventClickState, value: Int64(clicks))
        post(e)
    }
    private func setModifiers(_ value: Int) {
        let changed = modifiers ^ value
        for (bit, code) in Self.modifierKeys.enumerated() where changed & (1 << bit) != 0 {
            modifiers = (modifiers & ~(1 << bit)) | (value & (1 << bit))
            guard let e = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: value & (1 << bit) != 0) else { continue }
            e.type = .flagsChanged
            post(e)
        }
    }
}

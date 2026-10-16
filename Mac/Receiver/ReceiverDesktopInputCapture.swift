import AppKit

/// A local monitor is necessary to forward Command shortcuts before AppKit menu
/// dispatch. It never observes other apps or another DisplayWeave window.
@MainActor
final class ReceiverDesktopInputCapture {
    private weak var view: NSView?
    private weak var receiver: StreamReceiver?
    private var monitor: Any?
    private var focusObserver: NSObjectProtocol?
    private var buttons = Set<Int>()

    init(view: NSView, receiver: StreamReceiver) { self.view = view; self.receiver = receiver }

    func attach() {
        detach()
        guard let window = view?.window else { return }
        window.acceptsMouseMovedEvents = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp, .flagsChanged, .mouseMoved,
            .leftMouseDown, .leftMouseUp, .leftMouseDragged, .rightMouseDown, .rightMouseUp,
            .rightMouseDragged, .otherMouseDown, .otherMouseUp, .otherMouseDragged, .scrollWheel]) { [weak self] event in
                guard let self else { return event }
                return self.handle(event)
            }
        focusObserver = NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification,
            object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.release() }
            }
    }

    deinit {
        if let monitor { NSEvent.removeMonitor(monitor) }
        if let focusObserver { NotificationCenter.default.removeObserver(focusObserver) }
    }

    func release() { receiver?.releaseDesktopInput(); buttons.removeAll() }

    func detach() {
        release()
        if let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil }
        if let focusObserver { NotificationCenter.default.removeObserver(focusObserver); self.focusObserver = nil }
    }

    private func handle(_ event: NSEvent) -> NSEvent? {
        guard let view, let receiver, receiver.inputForwarding,
              let window = view.window, event.window === window, window.isKeyWindow else { return event }
        let flags = event.modifierFlags
        if event.type == .keyDown, event.keyCode == 53, flags.contains([.control, .option]) {
            release(); receiver.setInputForwarding(false); return nil
        }
        guard receiver.inputGrant != nil else { return event }
        let keyboard = event.type == .keyDown || event.type == .keyUp || event.type == .flagsChanged
        let down = [.leftMouseDown, .rightMouseDown, .otherMouseDown].contains(event.type)
        let up = [.leftMouseUp, .rightMouseUp, .otherMouseUp].contains(event.type)
        let dragged = [.leftMouseDragged, .rightMouseDragged, .otherMouseDragged].contains(event.type)
        if keyboard {
            guard window.firstResponder === view else { return event }
        } else if !down && window.firstResponder !== view { return event }
        var object: [String: Any] = ["modifiers": Self.modifiers(flags)]
        if keyboard {
            if event.type == .flagsChanged { object["kind"] = "modifiers" }
            else {
                object["kind"] = event.type == .keyDown ? "keyDown" : "keyUp"
                object["keyCode"] = event.keyCode; object["repeat"] = event.isARepeat
            }
        } else {
            guard let point = DesktopInputGeometry.normalized(view.convert(event.locationInWindow, from: nil),
                    in: view.bounds, video: receiver.videoSize, clamp: (up || dragged) && buttons.contains(event.buttonNumber)) else { return event }
            object["x"] = point.x; object["y"] = point.y
            if down || up {
                guard (0...2).contains(event.buttonNumber) else { return event }
                if down { window.makeFirstResponder(view); buttons.insert(event.buttonNumber) }
                else { guard buttons.remove(event.buttonNumber) != nil else { return event } }
                object["kind"] = down ? "buttonDown" : "buttonUp"
                object["button"] = event.buttonNumber; object["clicks"] = min(3, max(1, event.clickCount))
            } else if event.type == .scrollWheel {
                object["kind"] = "scroll"
                let scale = event.hasPreciseScrollingDeltas ? 1.0 : 10.0
                object["dx"] = min(4096, max(-4096, Double(event.scrollingDeltaX) * scale))
                object["dy"] = min(4096, max(-4096, Double(event.scrollingDeltaY) * scale))
            } else { object["kind"] = "move" }
        }
        receiver.sendDesktopInput(object)
        return nil
    }

    private static func modifiers(_ flags: NSEvent.ModifierFlags) -> Int {
        let fields: [NSEvent.ModifierFlags] = [.shift, .control, .option, .command, .capsLock]
        return fields.enumerated().reduce(0) { $0 | (flags.contains($1.element) ? 1 << $1.offset : 0) }
    }
}

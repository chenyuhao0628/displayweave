import AppKit

@main enum PencilAdvancedSelfTest {
    static func main() throws {
        let sample = PencilSample(phase: .down, x: 0.5, y: 0.5, pressure: 1, azimuth: 0,
                                  altitude: .pi / 2, roll: .pi / 2, tool: .eraser)!
        precondition(PencilSample(message: sample.extendedMessage)?.tool == .eraser)
        precondition(PencilSample(message: sample.extendedMessage)?.roll == .pi / 2)
        precondition(PencilSample(message: sample.message)?.tool == .pen)
        for bad: Any in [true, 100, "NaN"] {
            var object = sample.extendedMessage; object["roll"] = bad
            precondition(PencilSample(message: object) == nil)
        }
        var invalid = sample.extendedMessage; invalid["tool"] = "future"
        precondition(PencilSample(message: invalid) == nil)
        invalid = sample.message; invalid["pressure"] = true
        precondition(PencilSample(message: invalid) == nil)
        var forwarder = PencilInputForwarder()
        precondition(forwarder.messages(for: sample, enabled: true, extended: false)[0]["type"] as? String == "pencil")
        let move = PencilSample(phase: .move, x: 0.5, y: 0.5, pressure: 1, azimuth: 0, altitude: 0, roll: 1, tool: .eraser)!
        precondition(forwarder.messages(for: move, enabled: true, extended: true)[0]["type"] as? String == "pencil")
        _ = forwarder.messages(for: sample.cancelled, enabled: true, extended: true)
        precondition(forwarder.messages(for: sample, enabled: true, extended: true)[0]["type"] as? String == "pencil2")
        precondition(PencilGestureAction.system.resolve(system: .toggleEraser) == .toggleEraser)
        precondition(PencilGestureAction.system.resolve(system: .none) == .none)
        precondition(PencilGestureAction.undo.resolve(system: .none) == .undo)
        var gesture = PencilGestureDeduplicator()
        precondition(gesture.accept(1) && !gesture.accept(1) && !gesture.accept(.nan) && gesture.accept(2))
        var events: [CGEvent] = []
        let injector = InputInjector(displayID: 0, boundsProvider: { CGRect(x: 0, y: 0, width: 100, height: 100) }, eventSink: { events.append($0) })
        injector.handlePencil(sample)
        precondition(events[0].getIntegerValueField(.tabletProximityEventPointerType) == 3)
        precondition(events[0].getIntegerValueField(.tabletProximityEventCapabilityMask) & 0x2000 != 0)
        precondition(abs(events.last!.getDoubleValueField(.tabletEventRotation) - 90) < 0.1)
        let pen = PencilSample(phase: .down, x: 0.2, y: 0.2, pressure: 0.5, azimuth: 0, altitude: 0)!
        injector.handlePencil(pen)
        precondition(events.suffix(4).map(\.type) == [.leftMouseUp, .tabletProximity, .tabletProximity, .leftMouseDown])
        precondition(events[events.count - 2].getIntegerValueField(.tabletProximityEventPointerType) == 1)
        injector.handleShortcut(PencilShortcut(keyCode: 6, modifiers: 8)!)
        precondition(events.suffix(4).map(\.type) == [.flagsChanged, .keyDown, .keyUp, .flagsChanged])
        precondition(events[events.count - 2].flags.contains(.maskCommand))
        precondition(!events.last!.flags.contains(.maskCommand))
        precondition(PencilShortcut(keyCode: 55, modifiers: 0) == nil)
        var permission = true
        var permissionEvents: [CGEvent] = []
        let permissionInjector = InputInjector(displayID: 0, boundsProvider: { CGRect(x: 0, y: 0, width: 100, height: 100) },
            eventSink: { permissionEvents.append($0) }, permission: { permission })
        permissionInjector.handlePencil(sample)
        permission = false; permissionInjector.handlePencil(move)
        permission = true
        let afterLoss = permissionEvents.count
        permissionInjector.handlePencil(sample.cancelled)
        precondition(permissionEvents.count == afterLoss, "permission loss must clear owned state")
        let settings = UserDefaults(suiteName: "displayweave.pencil.test.\(UUID().uuidString)")!
        precondition(PencilShortcut.configured(.shortcut1, defaults: settings)?.keyCode == 14)
        settings.set(1270, forKey: "pencilShortcut1Key")
        precondition(PencilShortcut.configured(.shortcut1, defaults: settings) == nil)
        settings.removeObject(forKey: "pencilShortcut1Key")
        for sequence: Any in [true, 0, 1.5, -1] {
            let invalidAction = try JSONSerialization.data(withJSONObject: ["type": "pencilAction", "action": "undo",
                "inputSession": UUID().uuidString, "sequence": sequence])
            precondition(PencilActionMessage(invalidAction) == nil)
        }
        var consent = false, access = true, now = 1.0, changes = 0
        var actions: [PencilRemoteAction] = []
        let gate = PencilActionSender(consent: { consent }, accessibility: { access }, now: { now },
            onChange: { changes += 1 }, perform: { actions.append($0) })
        gate.begin(encrypted: true, supported: true)
        precondition(gate.session == nil && gate.status == "consentRequired")
        consent = true; gate.refresh()
        let session = gate.session!
        func action(_ sequence: Int, session: String? = nil) throws {
            gate.handle(try JSONSerialization.data(withJSONObject: ["type": "pencilAction", "action": "undo",
                "inputSession": session ?? gate.session ?? "", "sequence": sequence]))
        }
        for i in 1...6 { try action(i) }
        precondition(actions.count == 5)
        now = 2.01; try action(6); precondition(actions.count == 5, "rate-limited sequence must still be consumed")
        try action(7); precondition(actions.count == 6)
        access = false; gate.refresh(); precondition(gate.session == nil)
        access = true; gate.refresh(); precondition(gate.session != session)
        try action(8, session: session); precondition(actions.count == 6)
        gate.begin(encrypted: false, supported: true); precondition(gate.session == nil)
        gate.begin(encrypted: true, supported: false); precondition(gate.session == nil)
        gate.reset(); try action(10); precondition(actions.count == 6)
        precondition(changes > 0)
        print("Pencil v2 roll/eraser, stroke compatibility, gesture mapping, shortcut consent/grants/rate/cancellation PASS")
    }
}

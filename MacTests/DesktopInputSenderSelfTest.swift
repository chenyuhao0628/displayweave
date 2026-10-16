import AppKit

@main enum DesktopInputSenderSelfTest {
    static func main() throws {
        var consent = false, access = false
        var configs: [[String: Any]] = [], events: [CGEvent] = []
        var injector: DesktopInputInjector!
        let sender = DesktopInputSender(consent: { consent }, accessibility: { access }, factory: { id in
            let target = DesktopInputInjector(displayID: id,
                bounds: { CGRect(x: -1000, y: 20, width: 1000, height: 600) }, sink: { events.append($0) })
            injector = target
            return target
        }, send: { configs.append($0) })
        let caps = [DesktopInputProtocol.capability]
        sender.configure(displayID: 1)
        sender.hello(encrypted: false, capabilities: caps)
        precondition(configs.last?["inputStatus"] as? String == "secureRequired")
        sender.hello(encrypted: true, capabilities: caps)
        precondition(configs.last?["inputStatus"] as? String == "consentRequired")
        consent = true; sender.refresh()
        precondition(configs.last?["inputStatus"] as? String == "accessibilityRequired")
        access = true; sender.refresh()
        let first = configs.last?["inputSession"] as! String
        let count = configs.count; sender.refresh(); precondition(configs.count == count)
        var sequence = 0
        func input(_ kind: String, _ extras: [String: Any] = [:], session: String? = nil) throws {
            sequence += 1
            var object: [String: Any] = ["type": "desktopInput", "inputSession": session ?? (configs.last?["inputSession"] as? String ?? first),
                "sequence": sequence, "kind": kind, "modifiers": 0, "x": 1, "y": 1, "button": 0, "clicks": 2]
            object.merge(extras) { _, value in value }
            sender.handle(try JSONSerialization.data(withJSONObject: object))
        }
        try input("keyDown", ["keyCode": 0, "modifiers": 8])
        precondition(injector.keys == [0] && injector.modifiers == 8)
        precondition(events.last?.type == .keyDown && events.last?.flags.contains(.maskCommand) == true)
        try input("keyDown", ["keyCode": 0, "repeat": true, "modifiers": 8])
        precondition(events.last?.getIntegerValueField(.keyboardEventAutorepeat) == 1)
        try input("buttonDown", ["button": 1])
        precondition(events.last?.type == .rightMouseDown && events.last?.location == CGPoint(x: -1, y: 619))
        try input("move")
        precondition(events.last?.type == .rightMouseDragged)
        try input("buttonDown", ["button": 2])
        precondition(injector.buttons.count == 2)
        try input("scroll", ["dx": -12, "dy": 34])
        precondition(events.last?.type == .scrollWheel)
        try input("releaseAll")
        precondition(injector.keys.isEmpty && injector.buttons.isEmpty && injector.modifiers == 0)
        let released = events.count; try input("releaseAll"); precondition(events.count == released)
        try input("keyDown", ["keyCode": 1])
        sender.configure(displayID: 2)
        precondition(events.last?.type == .keyUp)
        let next = configs.last?["inputSession"] as! String
        precondition(next != first)
        let replacedCount = events.count
        try input("keyDown", ["keyCode": 2], session: first)
        precondition(events.count == replacedCount)
        try input("keyDown", ["keyCode": 2], session: next)
        consent = false; sender.refresh()
        precondition(events.last?.type == .keyUp && configs.last?["inputStatus"] as? String == "consentRequired")
        let deniedCount = events.count; try input("keyDown", ["keyCode": 2], session: next)
        precondition(events.count == deniedCount)
        consent = true; sender.refresh()
        try input("keyDown", ["keyCode": 3, "modifiers": 3])
        access = false; sender.refresh()
        precondition(injector.keys.isEmpty && injector.modifiers == 0)
        access = true; sender.refresh()
        for key in 0..<16 { try input("keyDown", ["keyCode": key]) }
        precondition(injector.keys.count == 16)
        try input("keyDown", ["keyCode": 16])
        precondition(injector.keys.isEmpty)
        sender.refresh()
        try input("keyDown", ["keyCode": 4])
        try input("keyDown", ["keyCode": true])
        precondition(injector.keys.isEmpty)
        sender.refresh()
        try input("buttonDown")
        sender.reset()
        precondition(injector.buttons.isEmpty)
        let resetCount = events.count; try input("keyDown", ["keyCode": 5])
        precondition(events.count == resetCount)
        sender.hello(encrypted: true, capabilities: [])
        try input("keyDown", ["keyCode": 5])
        precondition(events.count == resetCount)
        print("Desktop input sender consent, permission revocation, target/session isolation, repeats, drag, modifiers and bounded cancellation PASS")
    }
}

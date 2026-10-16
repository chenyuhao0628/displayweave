import AppKit

/// Owned by one sender queue and reset before a socket or capture target changes.
final class DesktopInputSender {
    private var gate = DesktopInputSequence()
    private var injector: DesktopInputInjector?
    private var supported = false
    private var encrypted = false
    private var lastReason: String?
    private let consent: () -> Bool
    private let accessibility: () -> Bool
    private let send: ([String: Any]) -> Void
    private let factory: (CGDirectDisplayID) -> DesktopInputInjector

    init(consent: @escaping () -> Bool = { UserDefaults.standard.bool(forKey: DesktopInputProtocol.consentKey) },
         accessibility: @escaping () -> Bool = { AXIsProcessTrusted() },
         factory: @escaping (CGDirectDisplayID) -> DesktopInputInjector = { DesktopInputInjector(displayID: $0) },
         send: @escaping ([String: Any]) -> Void) {
        self.consent = consent; self.accessibility = accessibility; self.send = send; self.factory = factory
    }

    func configure(displayID: CGDirectDisplayID) {
        injector?.cancel(); gate.begin(nil); lastReason = nil
        injector = factory(displayID)
        refresh()
    }
    func hello(encrypted: Bool, capabilities: [String]?) {
        injector?.cancel(); gate.begin(nil); lastReason = nil
        self.encrypted = encrypted
        supported = capabilities?.contains(DesktopInputProtocol.capability) == true
        refresh()
    }
    func reset(removeTarget: Bool = false) {
        injector?.cancel(); gate.begin(nil); lastReason = nil; supported = false; encrypted = false
        if removeTarget { injector = nil }
    }
    func refresh() {
        guard supported else { return }
        let reason = !encrypted ? "secureRequired" : !consent() ? "consentRequired"
            : !accessibility() ? "accessibilityRequired" : injector == nil ? "targetPending" : "ready"
        if reason == "ready" {
            guard gate.session == nil else { return }
            let session = UUID().uuidString
            gate.begin(session)
            send(["type": "inputConfig", "inputCaps": [DesktopInputProtocol.capability], "inputSession": session, "inputStatus": reason])
        } else {
            injector?.cancel(); gate.begin(nil)
            if reason != lastReason { send(["type": "inputConfig", "inputCaps": [], "inputStatus": reason]) }
        }
        lastReason = reason
    }
    func handle(_ data: Data) {
        refresh()
        guard gate.session != nil else { return }
        guard let event = DesktopInputEvent.decode(data) else {
            // Revoke this grant after malformed input; a later refresh issues a fresh grant.
            injector?.cancel(); gate.begin(nil); return
        }
        guard gate.accept(event) else { return }
        if injector?.handle(event) == false { gate.begin(nil) }
    }
}

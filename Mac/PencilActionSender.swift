import AppKit

/// Queue-owned grants. Named actions resolve only through local sender settings.
final class PencilActionSender {
    private(set) var session: String?
    private(set) var status = "unsupported"
    private var encrypted = false, supported = false
    private var sequence: UInt64 = 0
    private var times: [TimeInterval] = [] // at most five accepted actions
    private let consent: () -> Bool
    private let accessibility: () -> Bool
    private let targetReady: () -> Bool
    private let now: () -> TimeInterval
    private let onChange: () -> Void
    private let perform: (PencilRemoteAction) -> Void

    init(consent: @escaping () -> Bool = { UserDefaults.standard.bool(forKey: "allowPencilShortcuts") },
         accessibility: @escaping () -> Bool = { AXIsProcessTrusted() },
         targetReady: @escaping () -> Bool = { true },
         now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
         onChange: @escaping () -> Void, perform: @escaping (PencilRemoteAction) -> Void) {
        self.consent = consent; self.accessibility = accessibility; self.now = now
        self.targetReady = targetReady
        self.onChange = onChange; self.perform = perform
    }
    func begin(encrypted: Bool, supported: Bool) {
        reset(); self.encrypted = encrypted; self.supported = supported
        refresh(force: true)
    }
    func reset() { session = nil; sequence = 0; times = []; encrypted = false; supported = false; status = "unsupported" }
    func refresh(force: Bool = false) {
        let reason = !supported ? "unsupported" : !encrypted ? "secureRequired" : !consent() ? "consentRequired"
            : !accessibility() ? "accessibilityRequired" : !targetReady() ? "targetPending" : "ready"
        guard force || reason != status else { return }
        status = reason; session = reason == "ready" ? UUID().uuidString : nil
        sequence = 0; times = []
        onChange()
    }
    func handle(_ data: Data) {
        refresh()
        guard let session, let message = PencilActionMessage(data), message.session == session,
              message.sequence > sequence else { return }
        sequence = message.sequence
        let instant = now()
        times.removeAll { instant - $0 >= 1 }
        guard instant.isFinite, times.count < 5 else { return }
        times.append(instant)
        perform(message.action)
    }
}

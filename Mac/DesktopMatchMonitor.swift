import Foundation

@MainActor
final class DesktopMatchMonitor {
    private let center: NotificationCenter
    private let name: Notification.Name
    private let delay: TimeInterval
    private let cooldown: TimeInterval
    private let update: @MainActor () -> Bool
    private var observer: NSObjectProtocol?
    private var pending: Task<Void, Never>?
    private var lastRebuild: TimeInterval?

    init(center: NotificationCenter = .default, name: Notification.Name,
         delay: TimeInterval = 2.5, cooldown: TimeInterval = 10,
         update: @escaping @MainActor () -> Bool) {
        self.center = center
        self.name = name
        self.delay = delay
        self.cooldown = cooldown
        self.update = update
    }

    func start() {
        guard observer == nil else { return }
        observer = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.schedule() }
        }
        schedule()
    }

    func stop() {
        pending?.cancel()
        pending = nil
        if let observer { center.removeObserver(observer) }
        observer = nil
    }

    func reconsider() {
        guard observer != nil else { return }
        schedule()
    }

    deinit {
        pending?.cancel()
        if let observer { center.removeObserver(observer) }
    }

    private func schedule() {
        pending?.cancel()
        let now = ProcessInfo.processInfo.systemUptime
        let remaining = lastRebuild.map { max(0, cooldown - (now - $0)) } ?? 0
        let wait = max(delay, remaining)
        pending = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .seconds(wait)) } catch { return }
            guard let self, !Task.isCancelled, self.observer != nil else { return }
            self.pending = nil
            if self.update() { self.lastRebuild = ProcessInfo.processInfo.systemUptime }
        }
    }
}

import Foundation

@main struct DesktopMatchMonitorSelfTest {
    @MainActor static func main() async throws {
        let center = NotificationCenter()
        let name = Notification.Name("DesktopMatchMonitorSelfTest")
        var attempts = 0
        let monitor = DesktopMatchMonitor(center: center, name: name, delay: 0.05, cooldown: 0.25) {
            attempts += 1
            return true
        }
        monitor.start()
        for _ in 0..<10 { center.post(name: name, object: nil) }
        try await Task.sleep(for: .milliseconds(130))
        precondition(attempts == 1, "a burst of display notifications must coalesce")
        center.post(name: name, object: nil)
        try await Task.sleep(for: .milliseconds(100))
        precondition(attempts == 1, "a rebuild must respect the cooldown")
        try await Task.sleep(for: .milliseconds(220))
        precondition(attempts == 2, "the latest change must be reconsidered after cooldown")
        center.post(name: name, object: nil)
        monitor.stop()
        try await Task.sleep(for: .milliseconds(350))
        precondition(attempts == 2, "a stopped owner must not receive delayed updates")
        center.post(name: name, object: nil)
        try await Task.sleep(for: .milliseconds(100))
        precondition(attempts == 2, "stop must unregister the observer")

        var rebuilding = true
        var matched = false
        var checks = 0
        let resumed = DesktopMatchMonitor(center: center, name: name, delay: 0.05, cooldown: 0.25) {
            checks += 1
            guard !rebuilding else { return false }
            matched = true
            return true
        }
        resumed.start()
        center.post(name: name, object: nil)
        try await Task.sleep(for: .milliseconds(130))
        precondition(checks == 1 && !matched, "a notification can arrive while the display is rebuilding")
        rebuilding = false
        resumed.reconsider()
        try await Task.sleep(for: .milliseconds(130))
        precondition(checks == 2 && matched, "rebuild completion must recheck a change that arrived while busy")
        resumed.stop()
        resumed.reconsider()
        try await Task.sleep(for: .milliseconds(130))
        precondition(checks == 2, "reconsider must not revive a stopped monitor")
        print("Desktop match monitor: debounce, cooldown, latest update and teardown PASS")
    }
}

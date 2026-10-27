import Foundation

@main struct DesktopMatchMonitorSelfTest {
    @MainActor static func waitUntil(_ message: String, _ condition: () -> Bool) async throws {
        let deadline = ProcessInfo.processInfo.systemUptime + 10
        while !condition() {
            precondition(ProcessInfo.processInfo.systemUptime < deadline, message)
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    @MainActor static func main() async throws {
        let center = NotificationCenter()
        let name = Notification.Name("DesktopMatchMonitorSelfTest")
        let cooldown: TimeInterval = 0.25
        var attempts: [TimeInterval] = []
        let monitor = DesktopMatchMonitor(center: center, name: name, delay: 0.05, cooldown: cooldown) {
            attempts.append(ProcessInfo.processInfo.systemUptime)
            return true
        }
        monitor.start()
        for _ in 0..<10 { center.post(name: name, object: nil) }
        try await waitUntil("the first update must run") { !attempts.isEmpty }
        precondition(attempts.count == 1, "a burst of display notifications must coalesce")
        center.post(name: name, object: nil)
        // Let the check itself run after the cooldown, as it can on a busy CI host.
        try await Task.sleep(for: .milliseconds(350))
        try await waitUntil("the latest change must be reconsidered after cooldown") { attempts.count >= 2 }
        precondition(attempts.count == 2, "one change must schedule only one update")
        precondition(attempts[1] - attempts[0] >= cooldown - 0.001,
                     "a rebuild must respect the cooldown")
        center.post(name: name, object: nil)
        monitor.stop()
        try await Task.sleep(for: .milliseconds(350))
        precondition(attempts.count == 2, "a stopped owner must not receive delayed updates")
        center.post(name: name, object: nil)
        try await Task.sleep(for: .milliseconds(100))
        precondition(attempts.count == 2, "stop must unregister the observer")

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
        try await waitUntil("the busy monitor must check once") { checks >= 1 }
        precondition(checks == 1 && !matched, "a notification can arrive while the display is rebuilding")
        rebuilding = false
        resumed.reconsider()
        try await waitUntil("reconsider must run") { checks >= 2 }
        precondition(checks == 2 && matched, "rebuild completion must recheck a change that arrived while busy")
        resumed.stop()
        resumed.reconsider()
        try await Task.sleep(for: .milliseconds(130))
        precondition(checks == 2, "reconsider must not revive a stopped monitor")
        print("Desktop match monitor: debounce, cooldown, latest update and teardown PASS")
    }
}

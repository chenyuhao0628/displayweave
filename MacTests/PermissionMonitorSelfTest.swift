import Foundation

// Permission requests are outside this lifecycle test; init only reads status.
enum InputInjector { static func ensureAccessibilityPermission() -> Bool { false } }

@main struct PermissionMonitorSelfTest {
    @MainActor static func main() {
        weak var released: PermissionMonitor?
        autoreleasepool {
            let monitor = PermissionMonitor()
            released = monitor
        }
        guard released == nil else {
            fputs("FAIL: permission polling timer retained a discarded settings monitor\n", stderr)
            exit(1)
        }
        print("Permission monitor releases its polling timer PASS")
    }
}

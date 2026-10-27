import Foundation
import AppKit
import CoreGraphics

/// Interactive desktop check: creates then removes two temporary virtual displays.
@main struct MacVirtualDisplaySelfTest {
    @MainActor static func verify(scale: Int, width: Int = 800, height: Int = 600) async throws {
        var display = VirtualDisplay(name: "DisplayWeave scale self-test",
            pointsWide: width, pointsHigh: height,
            sizeInMillimeters: width == 800 ? CGSize(width: 185, height: 139) : CGSize(width: 600, height: 338),
            serialNum: UInt32(0x44570000 + scale + width), requestedRefreshRate: 60, backingScale: scale)
        guard let id = display?.displayID else { fatalError("virtual display creation failed for \(scale)x") }
        var matched = false
        for _ in 0..<40 {
            if let mode = CGDisplayCopyDisplayMode(id), mode.width == width, mode.height == height,
               mode.pixelWidth == width * scale, mode.pixelHeight == height * scale { matched = true; break }
            try await Task.sleep(for: .milliseconds(100))
        }
        // Exercise the maintenance loop before checking release.
        try await Task.sleep(for: .milliseconds(300))
        display = nil
        precondition(matched, "virtual display did not select \(scale)x geometry")
        for _ in 0..<40 {
            var ids = [CGDirectDisplayID](repeating: 0, count: 32)
            var count: UInt32 = 0
            // CGDisplayIsActive can return -1 for a retired ID. Membership in
            // the current online list is the reliable removal check.
            if CGGetOnlineDisplayList(32, &ids, &count) == .success,
               !ids.prefix(Int(count)).contains(id) {
                print("Virtual display \(width)x\(height)pt @\(scale)x geometry and release PASS")
                return
            }
            try await Task.sleep(for: .milliseconds(100))
        }
        fatalError("virtual display not removed")
    }
    private static func hasIndependentDisplay() -> Bool {
        var ids = [CGDirectDisplayID](repeating: 0, count: 32)
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(32, &ids, &count) == .success else { return false }
        return ids.prefix(Int(count)).contains {
            CGDisplayIsActive($0) > 0 && CGDisplayVendorNumber($0) != 0x5043
        }
    }

    @MainActor static func main() {
        setbuf(stdout, nil)
        guard hasIndependentDisplay() else {
            print("SKIP virtual display lifecycle: requires an active independent display; open the laptop lid or attach a physical monitor")
            return
        }
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        Task { @MainActor in
            do {
                for _ in 0..<3 { try await verify(scale: 1); try await verify(scale: 2) }
                let source = DesktopMatchReference(id: 1, bounds: CGRect(x: 0, y: 0, width: 2048, height: 1152),
                    isMain: true, isBuiltIn: true, eligible: true, physicalSize: nil)
                let receiver = DesktopGeometry(pointsWide: 2560, pointsHigh: 1440, scale: 2)
                let match = DesktopMatchPolicy.match(receiver: receiver, reference: source, receiverSize: nil)
                precondition(match.geometry == DesktopGeometry(pointsWide: 2048, pointsHigh: 1152, scale: 2))
                try await verify(scale: match.geometry.scale, width: match.geometry.pointsWide, height: match.geometry.pointsHigh)
                exit(0)
            }
            catch { print("FAIL: \(error)"); exit(1) }
        }
        app.run()
    }
}

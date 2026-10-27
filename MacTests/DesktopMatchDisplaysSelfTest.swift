import CoreGraphics
import Foundation

@main struct DesktopMatchDisplaysSelfTest {
    static func main() {
        guard let reference = DesktopMatchDisplays.reference(for: "read-only-test-\(UUID())") else {
            print("SKIP desktop reference enumeration: no eligible online display in this session")
            return
        }
        precondition(CGDisplayIsOnline(reference.id) != 0 && CGDisplayIsActive(reference.id) != 0)
        precondition(CGDisplayMirrorsDisplay(reference.id) == kCGNullDirectDisplay)
        precondition(!(CGDisplayVendorNumber(reference.id) == 0x5043
                       && CGDisplayModelNumber(reference.id) == 0x4F53))
        precondition(reference.bounds.width >= 2 && reference.bounds.height >= 2)
        print("Desktop reference enumeration PASS (read-only; physical size \(reference.physicalSize == nil ? "unknown" : "reported"))")
    }
}

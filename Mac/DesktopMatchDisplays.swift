import CoreGraphics
import Foundation

enum DesktopMatchDisplays {
    static func physicalSize(displayID: CGDirectDisplayID, bounds: CGRect) -> DesktopPhysicalSize? {
        guard bounds.width.isFinite, bounds.height.isFinite,
              (2...16384).contains(bounds.width), (2...16384).contains(bounds.height),
              !isDisplayWeave(displayID) else { return nil }
        let size = CGDisplayScreenSize(displayID)
        let mode = CGDisplayCopyDisplayMode(displayID)
        return DesktopPhysicalSize.validated(width: size.width, height: size.height,
            pointsWide: Int(bounds.width), pointsHigh: Int(bounds.height),
            pixelsWide: mode?.pixelWidth, pixelsHigh: mode?.pixelHeight)
    }

    static func reference(for device: String) -> DesktopMatchReference? {
        var count: UInt32 = 0
        var ids = [CGDirectDisplayID](repeating: 0, count: 256)
        guard CGGetOnlineDisplayList(UInt32(ids.count), &ids, &count) == .success else { return nil }
        let displays = ids.prefix(min(Int(count), ids.count)).map { id in
            let bounds = CGDisplayBounds(id)
            return DesktopMatchReference(id: id, bounds: bounds, isMain: id == CGMainDisplayID(),
                isBuiltIn: CGDisplayIsBuiltin(id) != 0,
                eligible: CGDisplayIsActive(id) != 0 && CGDisplayIsOnline(id) != 0
                    && CGDisplayMirrorsDisplay(id) == kCGNullDirectDisplay && !isDisplayWeave(id),
                physicalSize: physicalSize(displayID: id, bounds: bounds))
        }
        return DesktopMatchPolicy.reference(from: displays, adjacentTo: DisplayArrangement.savedBounds(for: device))
    }

    private static func isDisplayWeave(_ id: CGDirectDisplayID) -> Bool {
        CGDisplayVendorNumber(id) == 0x5043 && CGDisplayModelNumber(id) == 0x4F53
    }
}

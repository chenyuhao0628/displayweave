import Foundation
import CoreGraphics
import ImageIO

/// Cursor sprites share the same bounded representation on both Apple receivers.
struct ReceiverCursorImage {
    let image: CGImage
    let anchor: CGPoint
    let normalizedSize: CGSize

    static func decode(_ object: [String: Any]) -> ReceiverCursorImage? {
        guard let base64 = object["png"] as? String, base64.utf8.count <= 256 * 1024,
              let width = object["nw"] as? Double, let height = object["nh"] as? Double,
              width.isFinite, height.isFinite, width > 0, height > 0, width <= 1, height <= 1 else { return nil }
        let ax = object["ax"] as? Double ?? 0, ay = object["ay"] as? Double ?? 0
        guard ax.isFinite, ay.isFinite,
              let png = Data(base64Encoded: base64),
              let source = CGImageSourceCreateWithData(png as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let pixelsWide = properties[kCGImagePropertyPixelWidth] as? Int,
              let pixelsHigh = properties[kCGImagePropertyPixelHeight] as? Int,
              pixelsWide > 0, pixelsHigh > 0, pixelsWide <= 512, pixelsHigh <= 512,
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        return ReceiverCursorImage(image: image,
            anchor: CGPoint(x: ax, y: ay),
            normalizedSize: CGSize(width: width, height: height))
    }
}

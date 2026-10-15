import Foundation
import CoreGraphics
import ImageIO

@main
struct ReceiverCursorImageSelfTest {
    static func sprite(width: Int, height: Int) -> [String: Any] {
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let png = NSMutableData()
        let destination = CGImageDestinationCreateWithData(png, "public.png" as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, context.makeImage()!, nil)
        precondition(CGImageDestinationFinalize(destination))
        return ["png": (png as Data).base64EncodedString(), "nw": 0.1, "nh": 0.2, "ax": 0.5, "ay": 0.25]
    }

    static func main() {
        let valid = sprite(width: 16, height: 16)
        let decoded = ReceiverCursorImage.decode(valid)!
        precondition(decoded.image.width == 16 && decoded.anchor.x == 0.5)
        precondition(decoded.normalizedSize.height == 0.2)
        precondition(ReceiverCursorImage.decode(sprite(width: 513, height: 1)) == nil,
            "Reject oversized dimensions before pixel allocation")
        precondition(ReceiverCursorImage.decode(sprite(width: 1, height: 513)) == nil)
        precondition(ReceiverCursorImage.decode(sprite(width: 512, height: 512)) != nil)
        for (key, value) in [("nw", 0.0), ("nh", 2.0), ("nw", Double.nan), ("ax", Double.infinity)] {
            var invalid = valid; invalid[key] = value
            precondition(ReceiverCursorImage.decode(invalid) == nil)
        }
        var invalid = valid; invalid["png"] = "invalid-base64"
        precondition(ReceiverCursorImage.decode(invalid) == nil)
        invalid["png"] = String(repeating: "A", count: 256 * 1024 + 1)
        precondition(ReceiverCursorImage.decode(invalid) == nil)
        print("Cursor image: valid PNG, bounded bytes/dimensions and finite geometry PASS")
    }
}

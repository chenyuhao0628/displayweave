import Foundation
import CoreFoundation

enum DesktopInputProtocol {
    static let capability = "mac-input-v1"
    static let consentKey = "allowMacDesktopInput"
    static let maximumSequence: UInt64 = 9_007_199_254_740_991
    static func permits(encrypted: Bool, consent: Bool, accessibility: Bool, capabilities: [String]?) -> Bool {
        encrypted && consent && accessibility && capabilities?.contains(capability) == true
    }
}

struct DesktopInputEvent {
    enum Kind: String { case move, buttonDown, buttonUp, scroll, keyDown, keyUp, modifiers, releaseAll }
    let session: String
    let sequence: UInt64
    let kind: Kind
    let modifiers: Int
    let x: Double
    let y: Double
    let button: Int
    let clicks: Int
    let dx: Double
    let dy: Double
    let keyCode: UInt16
    let repeating: Bool

    static func decode(_ data: Data) -> Self? {
        guard data.count <= 4096,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              object["type"] as? String == "desktopInput",
              let session = object["inputSession"] as? String, UUID(uuidString: session) != nil,
              let raw = object["kind"] as? String, let kind = Kind(rawValue: raw),
              let sequence = number(object["sequence"], range: 1...Double(DesktopInputProtocol.maximumSequence), integer: true),
              let modifiers = number(object["modifiers"], range: 0...31, integer: true) else { return nil }
        let pointer = [.move, .buttonDown, .buttonUp, .scroll].contains(kind)
        let buttonEvent = kind == .buttonDown || kind == .buttonUp
        let keyboard = kind == .keyDown || kind == .keyUp
        guard let x = number(pointer ? object["x"] : 0, range: 0...1),
              let y = number(pointer ? object["y"] : 0, range: 0...1),
              let button = number(buttonEvent ? object["button"] : 0, range: 0...2, integer: true),
              let clicks = number(buttonEvent ? object["clicks"] : 1, range: 1...3, integer: true),
              let dx = number(kind == .scroll ? object["dx"] : 0, range: -4096...4096),
              let dy = number(kind == .scroll ? object["dy"] : 0, range: -4096...4096),
              let key = number(keyboard ? object["keyCode"] : 0, range: 0...127, integer: true) else { return nil }
        // Modifier keys use the aggregate modifier event, never a second held-key path.
        if keyboard && [54, 55, 56, 57, 58, 59, 60, 61, 62, 63].contains(Int(key)) { return nil }
        var repeating = false
        if let value = object["repeat"] {
            guard let n = value as? NSNumber, CFGetTypeID(n) == CFBooleanGetTypeID() else { return nil }
            repeating = n.boolValue
        }
        return Self(session: session, sequence: UInt64(sequence), kind: kind, modifiers: Int(modifiers),
                    x: x, y: y, button: Int(button), clicks: Int(clicks), dx: dx, dy: dy,
                    keyCode: UInt16(key), repeating: repeating)
    }

    private static func number(_ value: Any?, range: ClosedRange<Double>, integer: Bool = false) -> Double? {
        guard let n = value as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID() else { return nil }
        let value = n.doubleValue
        guard value.isFinite, range.contains(value), !integer || value.rounded(.towardZero) == value else { return nil }
        return value
    }
}

struct DesktopInputSequence {
    private(set) var session: String?
    private var last: UInt64 = 0
    mutating func begin(_ session: String?) { self.session = session; last = 0 }
    mutating func accept(_ event: DesktopInputEvent) -> Bool {
        guard event.session == session, event.sequence > last else { return false }
        last = event.sequence
        return true
    }
}

enum DesktopInputGeometry {
    /// AppKit points are bottom-up; wire video coordinates are top-down.
    static func normalized(_ point: CGPoint, in bounds: CGRect, video: CGSize, clamp: Bool = false) -> CGPoint? {
        guard [point.x, point.y, bounds.origin.x, bounds.origin.y, bounds.size.width, bounds.size.height, video.width, video.height].allSatisfy(\.isFinite),
              bounds.size.width > 0, bounds.size.height > 0, video.width > 0, video.height > 0 else { return nil }
        let scale = min(bounds.size.width / video.width, bounds.size.height / video.height)
        let width = video.width * scale, height = video.height * scale
        let x = (point.x - (bounds.origin.x + bounds.size.width / 2) + width / 2) / width
        let y = ((bounds.origin.y + bounds.size.height / 2) + height / 2 - point.y) / height
        guard clamp || ((0...1).contains(x) && (0...1).contains(y)) else { return nil }
        return CGPoint(x: min(1, max(0, x)), y: min(1, max(0, y)))
    }
}

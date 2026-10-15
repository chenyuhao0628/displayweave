import Foundation

/// Validate remote input before converting to CoreGraphics numeric types.
enum InputValidationPolicy {
    static func coordinate(_ value: Double) -> Double? {
        guard value.isFinite else { return nil }
        return min(1, max(0, value))
    }

    static func scroll(_ value: Double, scale: Double) -> Int32? {
        guard value.isFinite, scale.isFinite, scale > 0 else { return nil }
        return Int32(min(32768, max(-32768, (value / scale).rounded())))
    }
}

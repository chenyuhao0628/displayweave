import Foundation

enum FrameSizePolicy {
    static let legacyMaxBytes = 1 * 1_024 * 1_024
    static let v2DefaultMaxBytes = 8 * 1_024 * 1_024
    static let absoluteMaxBytes = 16 * 1_024 * 1_024

    static func negotiatedMaxBytes(
        supportsProtocolV2: Bool,
        capabilities: [String],
        advertisedBytes: Int?
    ) -> Int? {
        guard supportsProtocolV2,
              capabilities.contains("maxFrameBytes"),
              let advertisedBytes, advertisedBytes > 0 else { return nil }
        return min(advertisedBytes, absoluteMaxBytes)
    }

    static func permits(payloadBytes: Int, negotiatedMaxBytes: Int?) -> Bool {
        guard payloadBytes > 0 else { return false }
        guard let negotiatedMaxBytes else { return true }
        return payloadBytes <= min(negotiatedMaxBytes, absoluteMaxBytes)
    }
}

// Derived from peetzweg/opendisplay Shared/Protocol.swift
// Source: b9eec1f232fb5ea571c87e8392379a84f47b237f (GPL-3.0).
// DisplayWeave adaptations: LAN roles, bounded input and lifecycle isolation.

// Compiled into the DisplayWeave Mac target only.
// Keep this Foundation-only so it stays platform-neutral.

import Foundation

/// Upstream protocol namespace, independent of Android protocolVersion/DWV2.
enum WireProtocol {
    static let version = 3
}

/// One receiver-supported operating envelope. Every non-nil limit in an
/// entry applies together; multiple entries for the same codec are alternatives.
/// Codec names stay strings so older builds can ignore future codecs.
struct VideoCapability: Codable, Equatable {
    let codec: String
    let maxWidth: Int?
    let maxHeight: Int?
    let maxFrameRate: Int?
    let maxPixelsPerSecond: Int?

    init(codec: String, maxWidth: Int? = nil, maxHeight: Int? = nil,
         maxFrameRate: Int? = nil, maxPixelsPerSecond: Int? = nil) {
        self.codec = codec
        self.maxWidth = maxWidth
        self.maxHeight = maxHeight
        self.maxFrameRate = maxFrameRate
        self.maxPixelsPerSecond = maxPixelsPerSecond
    }
}

struct PanelAnnouncement: Codable, Equatable {
    let pixelsWide: Int
    let pixelsHigh: Int
    let scale: Double
    var pointsWide: Int? = nil
    var pointsHigh: Int? = nil

    var json: [String: Any] {
        var value: [String: Any] = ["pixelsWide": pixelsWide, "pixelsHigh": pixelsHigh, "scale": scale]
        if let pointsWide { value["pointsWide"] = pointsWide }
        if let pointsHigh { value["pointsHigh"] = pointsHigh }
        return value
    }
}

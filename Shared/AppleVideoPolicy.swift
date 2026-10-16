import Foundation

/// Conservative advertised envelope, not a measured hardware performance claim.
enum AppleVideoPolicy {
    static let capability = "appleVideoV1"
    static let maxPixelsPerSecond = 4096 * 2304 * 60
    static func frameRate(maximum: Int) -> Int {
        [120, 90, 60, 30].first(where: { $0 <= maximum }) ?? max(1, maximum)
    }
}

struct AppleVideoConfiguration: Equatable {
    let codec: ReceiverVideoCodec
    let width: Int
    let height: Int
    let fps: Int

    init?(_ object: [String: Any], maxWidth: Int, maxHeight: Int, maxFps: Int) {
        guard let codec = ReceiverVideoCodec(rawValue: object["codec"] as? String ?? "h264"),
              let width = object["width"] as? Int, let height = object["height"] as? Int,
              width >= 2, height >= 2, width <= min(8192, maxWidth), height <= min(8192, maxHeight),
              width % 2 == 0, height % 2 == 0 else { return nil }
        let fps = object["fps"] as? Int ?? object["framesPerSecond"] as? Int ?? 60
        guard fps >= 1, fps <= min(120, maxFps),
              width * height * fps <= AppleVideoPolicy.maxPixelsPerSecond else { return nil }
        self.codec = codec; self.width = width; self.height = height; self.fps = fps
    }
}

struct AppleVideoFallbackPolicy {
    private(set) var hevcFailed = false
    private var deadline: TimeInterval?
    var awaitingFallback: Bool { deadline != nil }
    mutating func failHEVC(now: TimeInterval) -> Bool {
        guard !hevcFailed else { return false }
        hevcFailed = true; deadline = now + 3
        return true
    }
    func accepts(_ codec: ReceiverVideoCodec) -> Bool { codec != .hevc || !hevcFailed }
    mutating func receivedH264() { deadline = nil }
    func expired(now: TimeInterval) -> Bool { deadline.map { now >= $0 } ?? false }
}

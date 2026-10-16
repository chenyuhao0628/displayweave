import Foundation

/// Queue-owned by the sender. The Mac receiver rejects HEVC for the remainder
/// of a connection once it has requested fallback, including after a resize.
struct MacCodecFallbackPolicy {
    private var hevcFailed = false

    mutating func beginConnection() { hevcFailed = false }
    mutating func recordFailure(_ codec: StreamCodec) {
        if codec == .hevc { hevcFailed = true }
    }
    func codec(for preferred: StreamCodec, isMacReceiver: Bool) -> StreamCodec {
        isMacReceiver && hevcFailed && preferred == .hevc ? .h264 : preferred
    }
}

struct MacStreamPlan: Equatable {
    let pointsWide: Int
    let pointsHigh: Int
    let scale: Int
    let width: Int
    let height: Int
    let fps: Int
    let codec: StreamCodec
}

enum MacReceiverPolicy {
    /// Preserve the desktop's logical geometry while fitting the encoded raster.
    /// HEVC remains inside a valid H.264 envelope for same-raster fallback.
    static func plan(info: PhoneInfo, settings: StreamSettings,
                     sourceWidth: Int? = nil, sourceHeight: Int? = nil,
                     hardwareHEVCEncode: Bool = false) -> MacStreamPlan {
        let panel = info.panel
        let scale = (panel?.scale ?? info.scale) >= 1.5 ? 2 : 1
        func dimension(_ value: Int) -> Int { min(16384, max(2, value)) & ~1 }
        let pw = dimension(panel?.pixelsWide ?? info.pixelsWide)
        let ph = dimension(panel?.pixelsHigh ?? info.pixelsHigh)
        let pointsWide = dimension(panel?.pointsWide ?? (pw / scale))
        let pointsHigh = dimension(panel?.pointsHigh ?? (ph / scale))
        let nativeW = dimension(sourceWidth ?? (pointsWide * scale))
        let nativeH = dimension(sourceHeight ?? (pointsHigh * scale))
        let portrait = nativeH > nativeW
        let fallbackW = portrait ? 2304 : 4096
        let fallbackH = portrait ? 4096 : 2304
        let h264Caps = (info.videoCaps ?? []).prefix(16).filter { $0.codec.lowercased() == "h264" }
        let fallback = h264Caps.isEmpty ? [VideoCapability(codec: "h264")] : h264Caps
        let hevcCaps = (info.videoCaps ?? []).prefix(16).filter { $0.codec.lowercased() == "hevc" }
        let hevc = hardwareHEVCEncode && settings.codecMode != .h264
            && info.negotiatedSupportedCodecs.contains("hevc") && !hevcCaps.isEmpty
        func intersect(_ a: Int?, _ b: Int?) -> Int? {
            if let a, let b { return min(a, b) }; return a ?? b
        }
        let offers = hevc ? hevcCaps.flatMap { cap in fallback.map { safe in
            VideoCapability(codec: "hevc", maxWidth: intersect(cap.maxWidth, safe.maxWidth),
                maxHeight: intersect(cap.maxHeight, safe.maxHeight),
                maxFrameRate: intersect(cap.maxFrameRate, safe.maxFrameRate),
                maxPixelsPerSecond: intersect(cap.maxPixelsPerSecond, safe.maxPixelsPerSecond))
        } } : fallback
        // Alternative envelopes are evaluated independently, never combined into
        // an operating point that no advertised capability can actually decode.
        let plans = offers.map { cap -> MacStreamPlan in
            let maxW = min(fallbackW, max(2, cap.maxWidth ?? fallbackW), max(2, info.maxEncodeWide ?? fallbackW))
            let maxH = min(fallbackH, max(2, cap.maxHeight ?? fallbackH), max(2, info.maxEncodeHigh ?? fallbackH))
            let pixelBudget = cap.maxPixelsPerSecond.map { max(4, $0) } ?? Int.max
            let ratio = min(settings.quality.scale, Double(maxW) / Double(nativeW), Double(maxH) / Double(nativeH),
                            sqrt(Double(pixelBudget) / Double(nativeW * nativeH)))
            var width = max(2, Int(Double(nativeW) * ratio) & ~1)
            var height = max(2, Int(Double(nativeH) * ratio) & ~1)
            // Rounding a very narrow raster up to two pixels must not exceed
            // even the one-frame throughput budget of the fallback decoder.
            if width * height > pixelBudget {
                if width >= height { width = max(2, (pixelBudget / height) & ~1) }
                else { height = max(2, (pixelBudget / width) & ~1) }
            }
            let budgetFps = cap.maxPixelsPerSecond.map { max(1, $0 / (width * height)) } ?? 60
            let limit = min(60, max(1, info.displayMaxFrameRate ?? info.maxFps ?? 60),
                            max(1, cap.maxFrameRate ?? 60), budgetFps,
                            settings.fpsMode.userSelectedFps ?? 60)
            let fps = limit >= 60 ? 60 : (limit >= 30 ? 30 : limit)
            return MacStreamPlan(pointsWide: pointsWide, pointsHigh: pointsHigh, scale: scale,
                                 width: width, height: height, fps: fps, codec: hevc ? .hevc : .h264)
        }
        return plans.max { $0.width * $0.height * $0.fps < $1.width * $1.height * $1.fps }!
    }
}

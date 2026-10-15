import Foundation

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
    /// Mac reception deliberately uses H.264 even when global mobile preferences use HEVC.
    static func plan(info: PhoneInfo, settings: StreamSettings,
                     sourceWidth: Int? = nil, sourceHeight: Int? = nil) -> MacStreamPlan {
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
        let caps = (info.videoCaps ?? []).filter { $0.codec.lowercased() == "h264" }
        let offers = caps.isEmpty ? [VideoCapability(codec: "h264")] : caps
        // Alternative envelopes are evaluated independently, never combined into
        // an operating point that no advertised capability can actually decode.
        let plans = offers.map { cap -> MacStreamPlan in
            let maxW = min(fallbackW, max(2, cap.maxWidth ?? info.maxEncodeWide ?? fallbackW))
            let maxH = min(fallbackH, max(2, cap.maxHeight ?? info.maxEncodeHigh ?? fallbackH))
            let ratio = min(settings.quality.scale, Double(maxW) / Double(nativeW), Double(maxH) / Double(nativeH))
            let width = max(2, Int(Double(nativeW) * ratio) & ~1)
            let height = max(2, Int(Double(nativeH) * ratio) & ~1)
            let budgetFps = cap.maxPixelsPerSecond.map { max(1, $0 / (width * height)) } ?? 60
            let limit = min(60, max(1, info.displayMaxFrameRate ?? info.maxFps ?? 60),
                            max(1, cap.maxFrameRate ?? 60), budgetFps,
                            settings.fpsMode.userSelectedFps ?? 60)
            let fps = limit >= 60 ? 60 : (limit >= 30 ? 30 : limit)
            return MacStreamPlan(pointsWide: pointsWide, pointsHigh: pointsHigh, scale: scale,
                                 width: width, height: height, fps: fps, codec: .h264)
        }
        return plans.max { $0.width * $0.height * $0.fps < $1.width * $1.height * $1.fps }!
    }
}

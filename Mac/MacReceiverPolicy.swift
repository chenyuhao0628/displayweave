import Foundation
import CoreGraphics

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

enum VirtualDisplayPhysicalSizePolicy {
    static let defaultMobileLandscapeMillimeters = CGSize(width: 208, height: 96)
    static let defaultMobilePortraitMillimeters = CGSize(width: 96, height: 208)
    static let minimumAreaSquareMillimeters: Double = 20_000
    static let maximumDimensionMillimeters: Double = 2_000

    static func clampedMillimeters(width: Double, height: Double) -> CGSize? {
        guard width.isFinite, height.isFinite, width > 0, height > 0 else { return nil }
        var w = width
        var h = height
        let maxEdge = max(w, h)
        if maxEdge > maximumDimensionMillimeters {
            let down = maximumDimensionMillimeters / maxEdge
            w *= down
            h *= down
        }
        let area = w * h
        if area < minimumAreaSquareMillimeters {
            let up = (minimumAreaSquareMillimeters / area).squareRoot()
            w *= up
            h *= up
        }
        if w > maximumDimensionMillimeters {
            w = maximumDimensionMillimeters
            h = max(h, minimumAreaSquareMillimeters / w)
        }
        if h > maximumDimensionMillimeters {
            h = maximumDimensionMillimeters
            w = max(w, minimumAreaSquareMillimeters / h)
        }
        if w * h < minimumAreaSquareMillimeters {
            let fix = (minimumAreaSquareMillimeters / (w * h)).squareRoot().nextUp
            w = min(maximumDimensionMillimeters, w * fix)
            h = min(maximumDimensionMillimeters, h * fix)
            if w * h < minimumAreaSquareMillimeters {
                if w <= h {
                    w = min(maximumDimensionMillimeters, (minimumAreaSquareMillimeters / h).nextUp)
                } else {
                    h = min(maximumDimensionMillimeters, (minimumAreaSquareMillimeters / w).nextUp)
                }
            }
        }
        return CGSize(width: w, height: h)
    }

    static func millimeters(
        for info: PhoneInfo,
        selection: DesktopResolution = .automatic,
        pointsWide: Int,
        pointsHigh: Int
    ) -> CGSize {
        let landscape = pointsWide == pointsHigh ? (info.pixelsWide >= info.pixelsHigh) : (pointsWide >= pointsHigh)
        if info.isMacReceiver {
            if selection == .automatic,
               let validated = MacReceiverPolicy.physicalSize(panel: info.panel),
               let clamped = clampedMillimeters(width: validated.width, height: validated.height) {
                return orient(clamped, landscape: landscape)
            }
            let fallbackW = Double(max(2, pointsWide)) * 25.4 / 110.0
            let fallbackH = Double(max(2, pointsHigh)) * 25.4 / 110.0
            return clampedMillimeters(width: fallbackW, height: fallbackH)
                ?? (landscape ? defaultMobileLandscapeMillimeters : defaultMobilePortraitMillimeters)
        }

        if let panel = info.panel,
           let rawW = panel.millimetersWide,
           let rawH = panel.millimetersHigh,
           rawW > 0, rawH > 0,
           let clamped = clampedMillimeters(width: Double(rawW), height: Double(rawH)) {
            return orient(clamped, landscape: landscape)
        }

        return landscape ? defaultMobileLandscapeMillimeters : defaultMobilePortraitMillimeters
    }

    private static func orient(_ size: CGSize, landscape: Bool) -> CGSize {
        let longEdge = max(size.width, size.height)
        let shortEdge = min(size.width, size.height)
        return landscape
            ? CGSize(width: longEdge, height: shortEdge)
            : CGSize(width: shortEdge, height: longEdge)
    }
}

enum MacReceiverPolicy {
    static let maxH264LongEdge = 4096
    static let maxH264ShortEdge = 2304

    static func clampedH264Dimensions(width: Int, height: Int) -> (width: Int, height: Int) {
        let safeW = max(2, min(16384, width))
        let safeH = max(2, min(16384, height))
        let portrait = safeH > safeW
        let maxW = portrait ? maxH264ShortEdge : maxH264LongEdge
        let maxH = portrait ? maxH264LongEdge : maxH264ShortEdge
        let ratio = min(1.0, Double(maxW) / Double(safeW), Double(maxH) / Double(safeH))
        return (
            max(2, Int(Double(safeW) * ratio) & ~1),
            max(2, Int(Double(safeH) * ratio) & ~1)
        )
    }
    static func physicalSize(panel: PanelAnnouncement?) -> DesktopPhysicalSize? {
        guard let panel, let width = panel.millimetersWide, let height = panel.millimetersHigh,
              (2...16384).contains(panel.pixelsWide), (2...16384).contains(panel.pixelsHigh),
              panel.scale.isFinite, (0.1...4).contains(panel.scale) else { return nil }
        return DesktopPhysicalSize.validated(width: Double(width), height: Double(height),
            pointsWide: panel.pointsWide ?? Int(Double(panel.pixelsWide) / panel.scale),
            pointsHigh: panel.pointsHigh ?? Int(Double(panel.pixelsHigh) / panel.scale),
            pixelsWide: panel.pixelsWide, pixelsHigh: panel.pixelsHigh)
    }

    static func desktop(info: PhoneInfo, settings: StreamSettings,
                        automaticReference: DesktopMatchReference? = nil) -> DesktopMatchResult {
        let panel = info.panel
        let scale = (panel?.scale ?? info.scale) >= 1.5 ? 2 : 1
        let selection = settings.desktopResolutions.resolution(for: info.id)
        let native = DesktopResolutionPolicy.geometry(selection,
            nativeWidth: panel?.pixelsWide ?? info.pixelsWide,
            nativeHeight: panel?.pixelsHigh ?? info.pixelsHigh,
            nativePointsWide: panel?.pointsWide, nativePointsHigh: panel?.pointsHigh, backingScale: scale)
        guard selection == .automatic, info.isMacReceiver else {
            return DesktopMatchResult(geometry: native, basis: .receiver)
        }
        return DesktopMatchPolicy.match(receiver: native, reference: automaticReference,
                                        receiverSize: physicalSize(panel: panel))
    }

    /// Preserve the desktop's logical geometry while fitting the encoded raster.
    /// HEVC remains inside a valid H.264 envelope for same-raster fallback.
    static func plan(info: PhoneInfo, settings: StreamSettings,
                     sourceWidth: Int? = nil, sourceHeight: Int? = nil,
                     hardwareHEVCEncode: Bool = false,
                     automaticReference: DesktopMatchReference? = nil) -> MacStreamPlan {
        func dimension(_ value: Int) -> Int { min(16384, max(2, value)) & ~1 }
        let desktop = desktop(info: info, settings: settings, automaticReference: automaticReference).geometry
        let scale = desktop.scale
        let pointsWide = desktop.pointsWide
        let pointsHigh = desktop.pointsHigh
        let nativeW = dimension(sourceWidth ?? (pointsWide * scale))
        let nativeH = dimension(sourceHeight ?? (pointsHigh * scale))
        let portrait = nativeH > nativeW
        let h264FallbackW = portrait ? maxH264ShortEdge : maxH264LongEdge
        let h264FallbackH = portrait ? maxH264LongEdge : maxH264ShortEdge
        let h264Caps = (info.videoCaps ?? []).prefix(16).filter { $0.codec.lowercased() == "h264" }
        let fallback = h264Caps.isEmpty ? [VideoCapability(codec: "h264")] : h264Caps
        let hevcCaps = (info.videoCaps ?? []).prefix(16).filter { $0.codec.lowercased() == "hevc" }
        let hevc = hardwareHEVCEncode && settings.codecMode != .h264
            && info.negotiatedSupportedCodecs.contains("hevc") && !hevcCaps.isEmpty
        let fallbackW = h264FallbackW
        let fallbackH = h264FallbackH
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
            let requestedFps = min(120, max(1, info.displayMaxFrameRate ?? info.maxFps ?? 60),
                                   max(1, cap.maxFrameRate ?? 60), settings.fpsMode.userSelectedFps ?? 120)
            let preferredFps = [120, 90, 60, 30].first(where: { $0 <= requestedFps }) ?? requestedFps
            let rasterBudget = settings.priority == .frameRate ? max(4, pixelBudget / preferredFps) : pixelBudget
            let ratio = min(settings.quality.scale, Double(maxW) / Double(nativeW), Double(maxH) / Double(nativeH),
                            sqrt(Double(rasterBudget) / Double(nativeW * nativeH)))
            var width = max(2, Int(Double(nativeW) * ratio) & ~1)
            var height = max(2, Int(Double(nativeH) * ratio) & ~1)
            // Rounding a very narrow raster up to two pixels must not exceed
            // even the one-frame throughput budget of the fallback decoder.
            if width * height > pixelBudget {
                if width >= height { width = max(2, (pixelBudget / height) & ~1) }
                else { height = max(2, (pixelBudget / width) & ~1) }
            }
            let budgetFps = cap.maxPixelsPerSecond.map { max(1, $0 / (width * height)) } ?? 120
            let limit = min(120, max(1, info.displayMaxFrameRate ?? info.maxFps ?? 60),
                            max(1, cap.maxFrameRate ?? 60), budgetFps,
                            settings.fpsMode.userSelectedFps ?? 120)
            let fps = [120, 90, 60, 30].first(where: { $0 <= limit }) ?? limit
            return MacStreamPlan(pointsWide: pointsWide, pointsHigh: pointsHigh, scale: scale,
                                 width: width, height: height, fps: fps, codec: hevc ? .hevc : .h264)
        }
        return plans.max { left, right in
            let leftPixels = left.width * left.height
            let rightPixels = right.width * right.height
            if settings.priority == .frameRate, left.fps != right.fps { return left.fps < right.fps }
            if leftPixels != rightPixels { return leftPixels < rightPixels }
            return left.fps < right.fps
        }!
    }
}

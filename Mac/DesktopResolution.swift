import Foundation

/// These are framebuffer pixels. HiDPI logical points remain a separate value.
enum DesktopResolution: String, CaseIterable {
    case native, fullHD, quadHD, ultraHD, iMac4K, iMac4_5K, iMac5K

    var label: String {
        switch self {
        case .native: return "跟随接收屏幕"
        case .fullHD: return "1080p · 1920×1080"
        case .quadHD: return "1440p · 2560×1440"
        case .ultraHD: return "4K · 3840×2160"
        case .iMac4K: return "iMac 4K · 4096×2304"
        case .iMac4_5K: return "iMac 4.5K · 4480×2520"
        case .iMac5K: return "iMac 5K · 5120×2880"
        }
    }
    var landscapePixels: (Int, Int)? {
        switch self {
        case .native: return nil
        case .fullHD: return (1920, 1080)
        case .quadHD: return (2560, 1440)
        case .ultraHD: return (3840, 2160)
        case .iMac4K: return (4096, 2304)
        case .iMac4_5K: return (4480, 2520)
        case .iMac5K: return (5120, 2880)
        }
    }

    func label(native: DesktopGeometry?) -> String {
        guard self == .native, let native else { return label }
        return "跟随接收屏幕 · \(native.pointsWide)×\(native.pointsHigh) 点"
    }
}

struct DesktopResolutionPreferences: Equatable {
    private var values: [String: DesktopResolution] = [:]
    init(stored: [String: String] = [:]) {
        for key in stored.keys.sorted().prefix(128) {
            if let resolution = DesktopResolution(rawValue: stored[key] ?? "") {
                set(resolution, for: key)
            }
        }
    }
    static func validIdentity(_ id: String?) -> Bool {
        guard let id else { return false }
        return !id.isEmpty && id.utf8.count <= 256
    }
    func resolution(for id: String?) -> DesktopResolution {
        guard let id, Self.validIdentity(id) else { return .native }
        return values[id] ?? .native
    }
    mutating func set(_ resolution: DesktopResolution, for id: String) {
        guard Self.validIdentity(id) else { return }
        if resolution == .native { values.removeValue(forKey: id); return }
        // User-selected entries only; retain a deterministic bounded history.
        if values[id] == nil, values.count >= 128, let oldest = values.keys.sorted().first {
            values.removeValue(forKey: oldest)
        }
        values[id] = resolution
    }
    var stored: [String: String] { values.mapValues(\.rawValue) }
}

struct DesktopGeometry: Equatable {
    let pointsWide: Int
    let pointsHigh: Int
    let scale: Int
    var pixelsWide: Int { pointsWide * scale }
    var pixelsHigh: Int { pointsHigh * scale }
    var summary: String {
        "桌面 \(pointsWide)×\(pointsHigh) 点 · \(scale == 2 ? "Retina 2×" : "1×") · \(pixelsWide)×\(pixelsHigh) 像素"
    }
}

enum DesktopResolutionPolicy {
    /// Android's FPS envelope describes the announced receiver raster. A mirror
    /// must fit that raster too; source display size is not decoder capability.
    static func mirrorRaster(sourceWidth: Int, sourceHeight: Int, qualityScale: Double,
                             maxWidth: Int, maxHeight: Int) -> (width: Int, height: Int) {
        raster(DesktopGeometry(pointsWide: max(2, min(16384, sourceWidth)),
                               pointsHigh: max(2, min(16384, sourceHeight)), scale: 1),
               qualityScale: qualityScale, maxWidth: maxWidth, maxHeight: maxHeight)
    }

    static func geometry(_ selection: DesktopResolution, nativeWidth: Int, nativeHeight: Int,
                         nativePointsWide: Int? = nil, nativePointsHigh: Int? = nil,
                         backingScale: Int) -> DesktopGeometry {
        let scale = backingScale == 1 ? 1 : 2
        func pixels(_ value: Int) -> Int { min(16384, max(4, value)) & ~1 }
        let width = pixels(nativeWidth), height = pixels(nativeHeight)
        let chosen: (Int, Int)? = selection.landscapePixels.map {
            height > width ? ($0.1, $0.0) : $0
        }
        func points(_ value: Int) -> Int { min(16384 / scale, max(2, value)) & ~1 }
        return DesktopGeometry(
            pointsWide: points(chosen.map { $0.0 / scale } ?? nativePointsWide ?? (width / scale)),
            pointsHigh: points(chosen.map { $0.1 / scale } ?? nativePointsHigh ?? (height / scale)),
            scale: scale)
    }

    /// Decoder bounds affect encoding only, never the selected virtual desktop.
    static func raster(_ desktop: DesktopGeometry, qualityScale: Double,
                       maxWidth: Int, maxHeight: Int) -> (width: Int, height: Int) {
        let quality = qualityScale.isFinite ? min(1, max(0.1, qualityScale)) : 1
        let ratio = min(quality, Double(max(2, min(16384, maxWidth))) / Double(desktop.pixelsWide),
                        Double(max(2, min(16384, maxHeight))) / Double(desktop.pixelsHigh))
        return (max(2, Int(Double(desktop.pixelsWide) * ratio) & ~1),
                max(2, Int(Double(desktop.pixelsHigh) * ratio) & ~1))
    }
}

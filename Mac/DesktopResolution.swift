import Foundation
import CoreGraphics

/// These are framebuffer pixels. HiDPI logical points remain a separate value.
enum DesktopResolution: String, CaseIterable {
    case automatic, native, fullHD, quadHD, ultraHD, iMac4K, iMac4_5K, iMac5K

    var label: String {
        switch self {
        case .automatic: return "自动匹配"
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
        case .automatic, .native: return nil
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
    let defaultResolution: DesktopResolution

    init(stored: [String: String] = [:], defaultResolution: DesktopResolution = .native) {
        self.defaultResolution = defaultResolution == .automatic ? .automatic : .native
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
        return values[id] ?? defaultResolution
    }
    mutating func set(_ resolution: DesktopResolution, for id: String) {
        guard Self.validIdentity(id) else { return }
        if resolution == defaultResolution { values.removeValue(forKey: id); return }
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

struct DesktopPhysicalSize: Equatable {
    let width: Double
    let height: Double

    /// Reported millimeters can be missing or synthesized by the display stack.
    static func validated(width: Double, height: Double, pointsWide: Int, pointsHigh: Int,
                          pixelsWide: Int? = nil, pixelsHigh: Int? = nil) -> DesktopPhysicalSize? {
        guard width.isFinite, height.isFinite, (50...2000).contains(width), (50...2000).contains(height),
              pointsWide >= 2, pointsHigh >= 2 else { return nil }
        let aspect = Double(pointsWide) / Double(pointsHigh)
        let normal = abs(log((width / height) / aspect))
        let rotated = abs(log((height / width) / aspect))
        let size = rotated < normal ? DesktopPhysicalSize(width: height, height: width)
                                    : DesktopPhysicalSize(width: width, height: height)
        guard min(normal, rotated) <= log(1.15) else { return nil }
        func synthetic(_ w: Int, _ h: Int) -> Bool {
            guard w >= 2, h >= 2 else { return false }
            return abs(size.width / (Double(w) * 25.4 / 72) - 1) < 0.02
                && abs(size.height / (Double(h) * 25.4 / 72) - 1) < 0.02
        }
        guard !synthetic(pointsWide, pointsHigh),
              !synthetic(pixelsWide ?? 0, pixelsHigh ?? 0) else { return nil }
        return size
    }
}

struct DesktopMatchReference {
    let id: UInt32
    let bounds: CGRect
    let isMain: Bool
    let isBuiltIn: Bool
    let eligible: Bool
    let physicalSize: DesktopPhysicalSize?
}

struct DesktopMatchResult {
    enum Basis { case physical, proportional, receiver }
    let geometry: DesktopGeometry
    let basis: Basis
}

enum DesktopMatchPolicy {
    static func reference(from displays: [DesktopMatchReference], adjacentTo saved: CGRect?) -> DesktopMatchReference? {
        let candidates = displays.filter {
            let b = $0.bounds
            return $0.eligible && b.origin.x.isFinite && b.origin.y.isFinite
                && b.width.isFinite && b.height.isFinite
                && (2...16384).contains(b.width) && (2...16384).contains(b.height)
        }
        func contact(_ display: CGRect, _ saved: CGRect?) -> CGFloat {
            guard let saved, !saved.isEmpty else { return -1 }
            let vertical = min(display.maxY, saved.maxY) - max(display.minY, saved.minY)
            let horizontal = min(display.maxX, saved.maxX) - max(display.minX, saved.minX)
            if (abs(display.maxX - saved.minX) < 1 || abs(saved.maxX - display.minX) < 1), vertical >= 0 {
                return vertical
            }
            if (abs(display.maxY - saved.minY) < 1 || abs(saved.maxY - display.minY) < 1), horizontal >= 0 {
                return horizontal
            }
            return -1
        }
        return candidates.max {
            let left = contact($0.bounds, saved), right = contact($1.bounds, saved)
            if left != right { return left < right }
            if $0.isMain != $1.isMain { return !$0.isMain }
            if $0.isBuiltIn != $1.isBuiltIn { return !$0.isBuiltIn }
            return $0.id > $1.id
        }
    }

    static func match(receiver: DesktopGeometry, reference: DesktopMatchReference?,
                      receiverSize: DesktopPhysicalSize?) -> DesktopMatchResult {
        guard let reference, reference.eligible, reference.bounds.width.isFinite,
              reference.bounds.height.isFinite, (2...16384).contains(reference.bounds.width),
              (2...16384).contains(reference.bounds.height),
              receiver.pointsWide >= 2, receiver.pointsHigh >= 2 else {
            return DesktopMatchResult(geometry: receiver, basis: .receiver)
        }
        let aspect = Double(receiver.pointsWide) / Double(receiver.pointsHigh)
        let width: Double
        let basis: DesktopMatchResult.Basis
        if let source = reference.physicalSize, let target = receiverSize,
           source.width.isFinite, target.width.isFinite, source.width > 0, target.width > 0 {
            let ratio = target.width / source.width
            width = Double(reference.bounds.width) * (abs(ratio - 1) < 0.05 ? 1 : ratio)
            basis = .physical
        } else {
            let longEdge = Double(max(reference.bounds.width, reference.bounds.height))
            width = receiver.pointsWide >= receiver.pointsHigh ? longEdge : longEdge * aspect
            basis = .proportional
        }
        let height = width / aspect
        // A smaller logical desktop on a 1x receiver needs extra backing
        // pixels to avoid magnifying text on that receiver.
        let receiverNeedsMorePixels = max(Double(receiver.pixelsWide) / width,
                                          Double(receiver.pixelsHigh) / height) > 1.05
        let scale = receiver.scale == 1 && !receiverNeedsMorePixels ? 1 : 2
        let edgeLimit = Double(16384 / scale)
        let areaLimit = 67_108_864.0 / Double(scale * scale)
        let limit = min(1, edgeLimit / width, edgeLimit / height, sqrt(areaLimit / (width * height)))
        func even(_ value: Double) -> Int { max(2, Int(value / 2) * 2) }
        let geometry = DesktopGeometry(pointsWide: even(width * limit), pointsHigh: even(height * limit), scale: scale)
        return DesktopMatchResult(geometry: geometry, basis: basis)
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

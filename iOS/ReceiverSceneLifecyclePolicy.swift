import Foundation

enum ReceiverSceneState: Equatable, Sendable {
    case active
    case inactive
    case background
}

enum ReceiverSceneAction: Equatable, Sendable {
    case startListening
    case stopListening
    case none
}

enum ReceiverSceneLifecyclePolicy {
    static func action(for state: ReceiverSceneState) -> ReceiverSceneAction {
        switch state {
        case .active: return .startListening
        case .inactive: return .none
        case .background: return .stopListening
        }
    }
}

struct ReceiverWindowGeometryResolution: Equatable, Sendable {
    let pixelsWide: Int
    let pixelsHigh: Int
    let scale: Double
    let pointsWide: Int
    let pointsHigh: Int
}

enum ReceiverWindowGeometryPolicy {
    static let minimumStreamPixels = 320
    static let maximumStreamPixels = 16384
    static let minimumScenePoints: Double = 320
    static let debounceIntervalSeconds: TimeInterval = 0.15

    static func clampEvenPixels(
        _ raw: Int,
        minimum: Int = minimumStreamPixels,
        maximum: Int = maximumStreamPixels
    ) -> Int {
        let evenMin = max(2, (minimum + 1) & ~1)
        let evenMax = max(evenMin, maximum & ~1)
        let clamped = max(evenMin, min(evenMax, raw))
        let even = clamped & ~1
        return even < evenMin ? evenMin : even
    }

    static func resolve(
        windowWidthPoints: Double,
        windowHeightPoints: Double,
        screenWidthPoints: Double,
        screenHeightPoints: Double,
        nativeLongPixels: Int,
        nativeShortPixels: Int,
        nativeScale: Double,
        screenScale: Double,
        isPhone: Bool,
        allowScreenFallbackWhenWindowInvalid: Bool
    ) -> ReceiverWindowGeometryResolution? {
        guard screenWidthPoints.isFinite, screenHeightPoints.isFinite,
              screenWidthPoints >= 2, screenHeightPoints >= 2 else {
            return nil
        }

        let hasPositiveWindow = windowWidthPoints.isFinite
            && windowHeightPoints.isFinite
            && windowWidthPoints > 0
            && windowHeightPoints > 0
        if !hasPositiveWindow && !allowScreenFallbackWhenWindowInvalid {
            return nil
        }

        let refWidth = hasPositiveWindow ? windowWidthPoints : screenWidthPoints
        let refHeight = hasPositiveWindow ? windowHeightPoints : screenHeightPoints
        guard refWidth.isFinite, refHeight.isFinite, refWidth > 0, refHeight > 0 else {
            return nil
        }

        let safeNativeScale = nativeScale.isFinite && nativeScale > 0 ? nativeScale : 2.0
        let safeScreenScale = screenScale.isFinite && screenScale > 0 ? screenScale : safeNativeScale
        let clampedNativeLong = clampEvenPixels(max(nativeLongPixels, nativeShortPixels))
        let clampedNativeShort = clampEvenPixels(min(nativeLongPixels, nativeShortPixels))

        let matchesFullScreen = !hasPositiveWindow
            || (abs(refWidth - screenWidthPoints) <= 2 && abs(refHeight - screenHeightPoints) <= 2)
            || (abs(refWidth - screenHeightPoints) <= 2 && abs(refHeight - screenWidthPoints) <= 2)

        let pixelsWide: Int
        let pixelsHigh: Int
        let effectiveScale: Double
        let pointsWide: Int
        let pointsHigh: Int

        if isPhone || matchesFullScreen {
            let portrait = refHeight > refWidth
            pixelsWide = portrait ? clampedNativeShort : clampedNativeLong
            pixelsHigh = portrait ? clampedNativeLong : clampedNativeShort
            effectiveScale = min(4.0, max(0.5, safeNativeScale))
            pointsWide = max(2, min(maximumStreamPixels, Int(refWidth.rounded())))
            pointsHigh = max(2, min(maximumStreamPixels, Int(refHeight.rounded())))
        } else {
            effectiveScale = min(4.0, max(0.5, safeScreenScale))
            let rawWide = Int((refWidth * effectiveScale).rounded())
            let rawHigh = Int((refHeight * effectiveScale).rounded())
            pixelsWide = clampEvenPixels(rawWide)
            pixelsHigh = clampEvenPixels(rawHigh)
            let clampedPtsWide = Int((Double(pixelsWide) / effectiveScale).rounded())
            let clampedPtsHigh = Int((Double(pixelsHigh) / effectiveScale).rounded())
            pointsWide = max(2, min(maximumStreamPixels,
                                    rawWide < minimumStreamPixels ? clampedPtsWide : Int(refWidth.rounded())))
            pointsHigh = max(2, min(maximumStreamPixels,
                                    rawHigh < minimumStreamPixels ? clampedPtsHigh : Int(refHeight.rounded())))
        }

        return ReceiverWindowGeometryResolution(
            pixelsWide: pixelsWide,
            pixelsHigh: pixelsHigh,
            scale: effectiveScale,
            pointsWide: pointsWide,
            pointsHigh: pointsHigh
        )
    }
}

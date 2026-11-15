import Foundation

private func check<T: Equatable>(_ expected: T, _ actual: T, _ message: String) {
    if expected != actual {
        fatalError("\(message): expected \(expected), got \(actual)")
    }
}

@main
struct ReceiverSceneLifecyclePolicySelfTest {
    static func main() {
        check(.startListening,
              ReceiverSceneLifecyclePolicy.action(for: .active),
              "the foreground receiver must listen")
        check(.none,
              ReceiverSceneLifecyclePolicy.action(for: .inactive),
              "temporary interruptions must not tear down the display")
        check(.stopListening,
              ReceiverSceneLifecyclePolicy.action(for: .background),
              "backgrounding must close the receiver connection")

        // iPadOS Split View / Slide Over / Stage Manager & foldable window geometry clamping
        check(320.0, ReceiverWindowGeometryPolicy.minimumScenePoints,
              "iPad scenes must enforce 320x320 minimum points")
        check(0.15, ReceiverWindowGeometryPolicy.debounceIntervalSeconds,
              "window resize re-hello must debounce by 150ms")
        check(320, ReceiverWindowGeometryPolicy.clampEvenPixels(0),
              "zero pixel edge must clamp to minimum 320px")
        check(320, ReceiverWindowGeometryPolicy.clampEvenPixels(199),
              "tiny split-divider pixel edge must clamp to minimum 320px")
        check(320, ReceiverWindowGeometryPolicy.clampEvenPixels(321),
              "odd pixel edge at minimum boundary must round down to even 320px")
        check(678, ReceiverWindowGeometryPolicy.clampEvenPixels(679),
              "odd split-divider pixel edge must clamp to even pixels")
        check(16384, ReceiverWindowGeometryPolicy.clampEvenPixels(99999),
              "oversized pixel edge must clamp to 16384px")

        // Transient zero/negative/NaN window bounds during live split-divider drags must be ignored
        check(nil,
              ReceiverWindowGeometryPolicy.resolve(
                windowWidthPoints: 0,
                windowHeightPoints: 1024,
                screenWidthPoints: 1366,
                screenHeightPoints: 1024,
                nativeLongPixels: 2732,
                nativeShortPixels: 2048,
                nativeScale: 2.0,
                screenScale: 2.0,
                isPhone: false,
                allowScreenFallbackWhenWindowInvalid: false
              ),
              "transient zero-width window geometry during live resize must be ignored")
        check(nil,
              ReceiverWindowGeometryPolicy.resolve(
                windowWidthPoints: .nan,
                windowHeightPoints: 800,
                screenWidthPoints: 1366,
                screenHeightPoints: 1024,
                nativeLongPixels: 2732,
                nativeShortPixels: 2048,
                nativeScale: 2.0,
                screenScale: 2.0,
                isPhone: false,
                allowScreenFallbackWhenWindowInvalid: false
              ),
              "non-finite window geometry during live resize must be ignored")

        // Tiny/odd Slide Over or Split View window clamps to >= 320 even pixels without dropping session
        let compactSplit = ReceiverWindowGeometryPolicy.resolve(
            windowWidthPoints: 155,
            windowHeightPoints: 511.5,
            screenWidthPoints: 1194,
            screenHeightPoints: 834,
            nativeLongPixels: 2388,
            nativeShortPixels: 1668,
            nativeScale: 2.0,
            screenScale: 2.0,
            isPhone: false,
            allowScreenFallbackWhenWindowInvalid: false
        )
        check(ReceiverWindowGeometryResolution(
            pixelsWide: 320,
            pixelsHigh: 1022,
            scale: 2.0,
            pointsWide: 160,
            pointsHigh: 512
        ), compactSplit, "compact/odd iPad Split View window must clamp to valid even >=320px dimensions")

        // Full-screen iPad window preserves exact native raster in both landscape and portrait
        let fullScreenPad = ReceiverWindowGeometryPolicy.resolve(
            windowWidthPoints: 1194,
            windowHeightPoints: 834,
            screenWidthPoints: 1194,
            screenHeightPoints: 834,
            nativeLongPixels: 2388,
            nativeShortPixels: 1668,
            nativeScale: 2.0,
            screenScale: 2.0,
            isPhone: false,
            allowScreenFallbackWhenWindowInvalid: false
        )
        check(ReceiverWindowGeometryResolution(
            pixelsWide: 2388,
            pixelsHigh: 1668,
            scale: 2.0,
            pointsWide: 1194,
            pointsHigh: 834
        ), fullScreenPad, "full-screen landscape iPad scene must preserve native panel pixels")

        let portraitPad = ReceiverWindowGeometryPolicy.resolve(
            windowWidthPoints: 834,
            windowHeightPoints: 1194,
            screenWidthPoints: 834,
            screenHeightPoints: 1194,
            nativeLongPixels: 2388,
            nativeShortPixels: 1668,
            nativeScale: 2.0,
            screenScale: 2.0,
            isPhone: false,
            allowScreenFallbackWhenWindowInvalid: false
        )
        check(ReceiverWindowGeometryResolution(
            pixelsWide: 1668,
            pixelsHigh: 2388,
            scale: 2.0,
            pointsWide: 834,
            pointsHigh: 1194
        ), portraitPad, "full-screen portrait iPad scene must preserve native portrait panel pixels")

        print("ReceiverSceneLifecyclePolicySelfTest PASS")
    }
}

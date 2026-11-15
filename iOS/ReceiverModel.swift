import SwiftUI
import AVFoundation
import UIKit
import Combine

// MARK: - Model

@MainActor
final class ReceiverModel: ObservableObject {
    let receiver: PhoneReceiver
    private var started = false
    private var cancellables = Set<AnyCancellable>()

    init() {
        receiver = PhoneReceiver(displayLayer: AVSampleBufferDisplayLayer())
        // Announce the active window scene's panel size to the Mac (avoiding
        // deprecated UIScreen.main on iOS 17+, with a safe fallback before a
        // scene attaches).
        if let scene = Self.activeWindowScene() {
            PhoneSceneSizing.applyMinimumSizeRestrictions(to: scene)
            applyScreenGeometry(
                scene: scene,
                windowBounds: .zero,
                allowScreenFallbackWhenWindowInvalid: true
            )
        } else {
            receiver.setNativePanel(long: 1920, short: 1080, scale: 2.0, maxFps: 60)
        }
        let savedName = UserDefaults.standard.string(forKey: "deviceName")
        let initialName = (savedName?.isEmpty == false) ? savedName! : UIDevice.current.name
        receiver.setServiceName(initialName)
        receiver.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
    }

    func start() {
        guard !started else { return }
        started = true
        receiver.start(port: 9000)
    }

    func updateWindowGeometry(scene: UIWindowScene?, windowBounds: CGRect) {
        guard let resolvedScene = scene ?? Self.activeWindowScene() else { return }
        PhoneSceneSizing.applyMinimumSizeRestrictions(to: resolvedScene)
        applyScreenGeometry(
            scene: resolvedScene,
            windowBounds: windowBounds,
            allowScreenFallbackWhenWindowInvalid: false
        )
    }

    private func applyScreenGeometry(
        scene: UIWindowScene,
        windowBounds: CGRect,
        allowScreenFallbackWhenWindowInvalid: Bool
    ) {
        let screen = scene.screen
        let native = screen.nativeBounds.size
        let rawLong = Int(max(native.width, native.height).rounded())
        let rawShort = Int(min(native.width, native.height).rounded())
        let nativeLong = ReceiverWindowGeometryPolicy.clampEvenPixels(rawLong)
        let nativeShort = ReceiverWindowGeometryPolicy.clampEvenPixels(rawShort)
        let nativeScale = screen.nativeScale > 0 ? Double(screen.nativeScale) : 2.0
        let screenScale = screen.scale > 0 ? Double(screen.scale) : nativeScale
        let maxFps = screen.maximumFramesPerSecond

        receiver.setNativePanel(
            long: nativeLong,
            short: nativeShort,
            scale: nativeScale,
            maxFps: maxFps
        )

        let screenSize = screen.bounds.size
        let isPhone = UIDevice.current.userInterfaceIdiom == .phone
        guard let resolved = ReceiverWindowGeometryPolicy.resolve(
            windowWidthPoints: Double(windowBounds.width),
            windowHeightPoints: Double(windowBounds.height),
            screenWidthPoints: Double(screenSize.width),
            screenHeightPoints: Double(screenSize.height),
            nativeLongPixels: nativeLong,
            nativeShortPixels: nativeShort,
            nativeScale: nativeScale,
            screenScale: screenScale,
            isPhone: isPhone,
            allowScreenFallbackWhenWindowInvalid: allowScreenFallbackWhenWindowInvalid
        ) else { return }

        receiver.setWindowGeometry(
            pixelsWide: resolved.pixelsWide,
            pixelsHigh: resolved.pixelsHigh,
            scale: resolved.scale,
            pointsWide: resolved.pointsWide,
            pointsHigh: resolved.pointsHigh,
            screenNativeLong: nativeLong,
            screenNativeShort: nativeShort,
            screenNativeScale: nativeScale
        )
    }

    private static func activeWindowScene() -> UIWindowScene? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        return scenes.first(where: { $0.activationState == .foregroundActive })
            ?? scenes.first(where: { $0.activationState == .foregroundInactive })
            ?? scenes.first
    }
}

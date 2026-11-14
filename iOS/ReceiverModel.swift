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
            applyScreenGeometry(scene: scene, windowBounds: .zero)
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
        applyScreenGeometry(scene: resolvedScene, windowBounds: windowBounds)
    }

    private func applyScreenGeometry(scene: UIWindowScene, windowBounds: CGRect) {
        let screen = scene.screen
        let native = screen.nativeBounds.size
        let nativeLong = max(2, Int(max(native.width, native.height).rounded()) & ~1)
        let nativeShort = max(2, Int(min(native.width, native.height).rounded()) & ~1)
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
        let hasValidWindow = windowBounds.width.isFinite && windowBounds.height.isFinite
            && windowBounds.width >= 64 && windowBounds.height >= 64
        let refSize = hasValidWindow ? windowBounds.size : screenSize
        guard refSize.width.isFinite, refSize.height.isFinite,
              refSize.width >= 2, refSize.height >= 2 else { return }

        let isPhone = UIDevice.current.userInterfaceIdiom == .phone
        let matchesFullScreen = !hasValidWindow
            || (abs(windowBounds.width - screenSize.width) <= 2
                && abs(windowBounds.height - screenSize.height) <= 2)
            || (abs(windowBounds.width - screenSize.height) <= 2
                && abs(windowBounds.height - screenSize.width) <= 2)

        let pixelsWide: Int
        let pixelsHigh: Int
        let effectiveScale: Double
        if isPhone || matchesFullScreen {
            let portrait = refSize.height > refSize.width
            pixelsWide = portrait ? nativeShort : nativeLong
            pixelsHigh = portrait ? nativeLong : nativeShort
            effectiveScale = min(4.0, max(0.5, nativeScale))
        } else {
            effectiveScale = min(4.0, max(0.5, screenScale))
            pixelsWide = max(2, min(16384, Int((refSize.width * effectiveScale).rounded()) & ~1))
            pixelsHigh = max(2, min(16384, Int((refSize.height * effectiveScale).rounded()) & ~1))
        }
        let pointsWide = max(2, min(16384, Int(refSize.width.rounded())))
        let pointsHigh = max(2, min(16384, Int(refSize.height.rounded())))

        receiver.setWindowGeometry(
            pixelsWide: pixelsWide,
            pixelsHigh: pixelsHigh,
            scale: effectiveScale,
            pointsWide: pointsWide,
            pointsHigh: pointsHigh,
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

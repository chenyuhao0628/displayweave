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
            let screen = scene.screen
            let native = screen.nativeBounds.size
            let nativeScale = screen.nativeScale > 0 ? Double(screen.nativeScale) : 2.0
            receiver.setNativePanel(
                long: max(2, Int(max(native.width, native.height).rounded()) & ~1),
                short: max(2, Int(min(native.width, native.height).rounded()) & ~1),
                scale: nativeScale,
                maxFps: screen.maximumFramesPerSecond
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

    private static func activeWindowScene() -> UIWindowScene? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        return scenes.first(where: { $0.activationState == .foregroundActive })
            ?? scenes.first(where: { $0.activationState == .foregroundInactive })
            ?? scenes.first
    }
}

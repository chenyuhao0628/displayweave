import SwiftUI
import AVFoundation
import UIKit
import Combine

/// "iPad" or "iPhone" — so UI copy names the device the user is holding.
let deviceKind = UIDevice.current.userInterfaceIdiom == .pad ? "iPad" : "iPhone"

/// Landing page — hosts the Mac app download and explains the two-app setup.
let macAppURL = URL(string: "https://chenyuhao0628.github.io/displayweave/")!

enum PhoneSceneSizing {
    @MainActor
    static func applyMinimumSizeRestrictions(to scene: UIWindowScene?) {
        guard let scene else { return }
        let isPad = scene.traitCollection.userInterfaceIdiom == .pad
            || UIDevice.current.userInterfaceIdiom == .pad
        guard isPad else { return }
        let minSide = CGFloat(ReceiverWindowGeometryPolicy.minimumScenePoints)
        scene.sizeRestrictions?.minimumSize = CGSize(width: minSide, height: minSide)
    }
}

final class PhoneSceneDelegate: NSObject, UIWindowSceneDelegate {
    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        PhoneSceneSizing.applyMinimumSizeRestrictions(to: scene as? UIWindowScene)
    }

    func sceneDidBecomeActive(_ scene: UIScene) {
        PhoneSceneSizing.applyMinimumSizeRestrictions(to: scene as? UIWindowScene)
    }
}

final class PhoneAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(
            name: connectingSceneSession.configuration.name,
            sessionRole: connectingSceneSession.role
        )
        configuration.delegateClass = PhoneSceneDelegate.self
        return configuration
    }
}

@main
struct OpenSidecarPhoneApp: App {
    @UIApplicationDelegateAdaptor(PhoneAppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            ReceiverScreen()
        }
    }
}

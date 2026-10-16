import Foundation
import Security
import Darwin
#if os(iOS)
import UIKit

@main final class KeychainTestApp: UIResponder, UIApplicationDelegate {
    var window: UIWindow?
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = UIViewController()
        window.makeKeyAndVisible()
        self.window = window
        // Complete launch before performing the isolated Keychain test. Keep
        // the app alive so simctl can reliably observe successful launch.
        DispatchQueue.main.async { AppleSecurityStoreSelfTest.main() }
        return true
    }
}
#else
@main enum KeychainTestCommand {
    static func main() { AppleSecurityStoreSelfTest.main() }
}
#endif

enum AppleSecurityStoreSelfTest {
    static func main() {
        let result: String
        do {
            try checkStore()
            result = "Apple Keychain: persistent identity/trust, explicit rotation, missing-key repair, tombstones and stale-state invalidation PASS"
        } catch {
            result = "Apple Keychain FAIL: \(error.localizedDescription)"
        }
#if os(iOS)
        let output = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("keychain-test-result.txt")
        try? Data(result.utf8).write(to: output, options: .atomic)
#endif
        print(result)
#if !os(iOS)
        if !result.hasSuffix("PASS") { exit(1) }
#endif
    }

    private static func checkStore() throws {
        // This random test namespace can never address the installed app's
        // identity. Remove only items created under this run's namespace.
        let scope = "app.displayweave.security-self-test." + UUID().uuidString
        let service = scope + ".transport-security.v1"
        defer {
            SecItemDelete([kSecClass: kSecClassKey, kSecAttrKeyType: kSecAttrKeyTypeECSECPrimeRandom,
                kSecAttrApplicationTag: Data((service + ".private-key").utf8)]
                .merging(AppleSecurityStore.storageAttributes) { _, new in new } as CFDictionary)
            SecItemDelete([kSecClass: kSecClassGenericPassword, kSecAttrService: service]
                .merging(AppleSecurityStore.storageAttributes) { _, new in new } as CFDictionary)
        }
        let first = AppleSecurityStore(scope: scope)
        let identity = try first.identity()
        let state = try first.pairingState(localID: "test-installation")
        let remote = try AppleTransportIdentity.ephemeral()
        try state.trustConfirmedReceiver(id: "test-peer", name: "Fixture", fingerprint: remote.fingerprint,
                                         explicitInvitation: true)
        let reopened = AppleSecurityStore(scope: scope)
        let restoredIdentity = try reopened.identity()
        let restored = try reopened.pairingState(localID: "test-installation")
        precondition(restoredIdentity.fingerprint == identity.fingerprint)
        precondition(restored.trustedPeer("test-peer")?.certificateSHA256 == remote.fingerprint)
        try first.resetIdentity(localID: "test-installation")
        let reset = AppleSecurityStore(scope: scope)
        let newIdentity = try reset.identity(), newState = try reset.pairingState(localID: "test-installation")
        precondition(newIdentity.fingerprint != identity.fingerprint)
        precondition(newState.hasPairingHistory("test-peer") && newState.trustedPeer("test-peer") == nil)
        precondition(!state.acceptsTLS(remote.fingerprint))
        // A missing key must never silently mint a new identity. Explicit
        // rotation still repairs it without removing downgrade history.
        let keyQuery: [CFString: Any] = [kSecClass: kSecClassKey, kSecAttrKeyType: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrApplicationTag: Data((service + ".private-key").utf8)]
            .merging(AppleSecurityStore.storageAttributes) { _, new in new }
        precondition(SecItemDelete(keyQuery as CFDictionary) == errSecSuccess)
        let lost = AppleSecurityStore(scope: scope)
        do { _ = try lost.identity(); preconditionFailure("missing key was silently replaced") } catch { }
        try lost.resetIdentity(localID: "test-installation")
        let repaired = try lost.context(localID: "test-installation")
        precondition(repaired.identity.fingerprint == repaired.pairing.localFingerprint)
        precondition(repaired.pairing.hasPairingHistory("test-peer"))
    }
}

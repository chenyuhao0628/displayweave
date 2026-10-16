import Foundation
import Security
import Darwin

/// Used only by test-mac-signing-runtime.py in a random disposable namespace.
@main enum SigningUpgradeSelfTest {
    static func main() throws {
        let args = CommandLine.arguments
        guard args.count == 4, args[2].hasPrefix("app.displayweave.signing-test."),
              UUID(uuidString: String(args[2].dropFirst("app.displayweave.signing-test.".count))) != nil else {
            exit(64)
        }
        // Never ask for access to an existing Keychain record during a test.
        SecKeychainSetUserInteractionAllowed(false)
        let phase = args[1], scope = args[2], output = URL(fileURLWithPath: args[3])
        let service = scope + ".transport-security.v1"
        if phase == "cleanup" {
            let queries: [[CFString: Any]] = [
                [kSecClass: kSecClassKey, kSecAttrKeyType: kSecAttrKeyTypeECSECPrimeRandom,
                 kSecAttrApplicationTag: Data((service + ".private-key").utf8)],
                [kSecClass: kSecClassGenericPassword, kSecAttrService: service]
            ]
            for query in queries {
                let status = SecItemDelete(query as CFDictionary)
                precondition(status == errSecSuccess || status == errSecItemNotFound)
            }
            print("cleanup PASS")
            return
        }
        let store = AppleSecurityStore(scope: scope)
        let identity = try store.identity()
        let state = try store.pairingState(localID: "test-installation")
        if phase == "seed" {
            let peer = try AppleTransportIdentity.ephemeral()
            try state.trustConfirmedReceiver(id: "test-peer", name: "Signing fixture",
                                            fingerprint: peer.fingerprint, explicitInvitation: true)
            let record = ["identity": identity.fingerprint, "peer": peer.fingerprint]
            try JSONEncoder().encode(record).write(to: output, options: .atomic)
        } else if phase == "check" {
            let record = try JSONDecoder().decode([String: String].self, from: Data(contentsOf: output))
            precondition(identity.fingerprint == record["identity"], "Local identity changed after upgrade")
            precondition(state.trustedPeer("test-peer")?.certificateSHA256 == record["peer"],
                         "Paired device was lost after upgrade")
        } else {
            exit(64)
        }
#if FIRST_SIGNED_BUILD
        print("first signed build: \(phase) PASS")
#else
        print("second signed build: \(phase) PASS")
#endif
    }
}

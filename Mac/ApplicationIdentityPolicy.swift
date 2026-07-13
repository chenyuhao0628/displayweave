import Foundation

enum ApplicationIdentityPolicy {
    static let releaseBundleIdentifier = "app.displayweave.mac"
    static let debugBundleIdentifier = "app.displayweave.mac.debug"
    private static let migrationMarker = "displayWeaveIdentityMigrationV1"

    static func legacyDomains(for bundleIdentifier: String?) -> [String] {
        if bundleIdentifier == debugBundleIdentifier {
            return [
                "com.peetzweg.opensidecar.mac.debug",
                "com.peetzweg.opensidecar.mac",
                "sh.peet.opensidecar.mac"
            ]
        }
        return [
            "com.peetzweg.opensidecar.mac",
            "com.peetzweg.opensidecar.mac.debug",
            "sh.peet.opensidecar.mac"
        ]
    }

    static func mergedPreferences(current: [String: Any],
                                  legacyDomains: [[String: Any]]) -> [String: Any] {
        var merged = current
        for domain in legacyDomains {
            for (key, value) in domain where merged[key] == nil {
                merged[key] = value
            }
        }
        return merged
    }

    static func migratePreferences(defaults: UserDefaults = .standard,
                                   bundleIdentifier: String? = Bundle.main.bundleIdentifier) {
        let domains = legacyDomains(for: bundleIdentifier).compactMap {
            defaults.persistentDomain(forName: $0)
        }
        migratePreferences(defaults: defaults, legacyDomainValues: domains)
    }

    static func migratePreferences(defaults: UserDefaults,
                                   legacyDomainValues: [[String: Any]]) {
        guard !defaults.bool(forKey: migrationMarker) else { return }
        let current = defaults.dictionaryRepresentation()
        let merged = mergedPreferences(current: current, legacyDomains: legacyDomainValues)
        for (key, value) in merged where current[key] == nil {
            defaults.set(value, forKey: key)
        }
        defaults.set(true, forKey: migrationMarker)
    }
}

import Foundation

private func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

@main
enum ApplicationIdentityPolicySelfTest {
    static func main() {
        expect(ApplicationIdentityPolicy.releaseBundleIdentifier == "app.displayweave.mac",
               "release identity is DisplayWeave-owned")
        expect(ApplicationIdentityPolicy.debugBundleIdentifier == "app.displayweave.mac.debug",
               "debug identity is isolated from OpenDisplay")
        expect(ApplicationIdentityPolicy.legacyDomains(for: "app.displayweave.mac.debug").first
               == "com.peetzweg.opensidecar.mac.debug",
               "debug migration prefers the matching legacy domain")

        let merged = ApplicationIdentityPolicy.mergedPreferences(
            current: ["quality": "high"],
            legacyDomains: [
                ["quality": "low", "fpsMode": "fps120"],
                ["codecMode": "hevc"]
            ])
        expect(merged["quality"] as? String == "high",
               "migration never overwrites current preferences")
        expect(merged["fpsMode"] as? String == "fps120",
               "migration copies missing matching-domain preferences")
        expect(merged["codecMode"] as? String == "hevc",
               "migration copies missing fallback-domain preferences")

        let suiteName = "ApplicationIdentityPolicySelfTest.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            fputs("FAIL: could not create isolated defaults suite\n", stderr)
            exit(1)
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set("manual", forKey: "bitrateMode")
        ApplicationIdentityPolicy.migratePreferences(
            defaults: defaults,
            legacyDomainValues: [["bitrateMode": "auto", "fpsMode": "fps120"]])
        expect(defaults.string(forKey: "bitrateMode") == "manual",
               "end-to-end migration preserves current-domain values")
        expect(defaults.string(forKey: "fpsMode") == "fps120",
               "end-to-end migration copies missing legacy values")
        ApplicationIdentityPolicy.migratePreferences(
            defaults: defaults,
            legacyDomainValues: [["transportMode": "usb"]])
        expect(defaults.object(forKey: "transportMode") == nil,
               "migration marker prevents a second migration")
        print("ApplicationIdentityPolicySelfTest PASS")
    }
}

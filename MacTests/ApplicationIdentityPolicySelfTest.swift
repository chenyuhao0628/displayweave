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
        expect(!ApplicationIdentityPolicy.testPatternEnabled(
            bundleIdentifier: ApplicationIdentityPolicy.releaseBundleIdentifier,
            storedValue: true),
            "release builds ignore an already-migrated test pattern value")
        expect(ApplicationIdentityPolicy.testPatternEnabled(
            bundleIdentifier: ApplicationIdentityPolicy.debugBundleIdentifier,
            storedValue: true),
            "debug builds may explicitly enable the test pattern")
        expect(!ApplicationIdentityPolicy.testPatternEnabled(
            bundleIdentifier: ApplicationIdentityPolicy.debugBundleIdentifier,
            storedValue: false),
            "debug builds keep the test pattern off by default")

        let merged = ApplicationIdentityPolicy.mergedPreferences(
            current: ["quality": "high"],
            legacyDomains: [
                ["quality": "low", "fpsMode": "fps120", "testPattern": true],
                ["codecMode": "hevc"]
            ])
        expect(merged["quality"] as? String == "high",
               "migration never overwrites current preferences")
        expect(merged["fpsMode"] as? String == "fps120",
               "migration copies missing matching-domain preferences")
        expect(merged["codecMode"] as? String == "hevc",
               "migration copies missing fallback-domain preferences")
        expect(merged["testPattern"] == nil,
               "migration never copies the debug-only test pattern")

        let suiteName = "ApplicationIdentityPolicySelfTest.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            fputs("FAIL: could not create isolated defaults suite\n", stderr)
            exit(1)
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set("manual", forKey: "bitrateMode")
        ApplicationIdentityPolicy.migratePreferences(
            defaults: defaults,
            legacyDomainValues: [[
                "bitrateMode": "auto",
                "fpsMode": "fps120",
                "testPattern": true
            ]])
        expect(defaults.string(forKey: "bitrateMode") == "manual",
               "end-to-end migration preserves current-domain values")
        expect(defaults.string(forKey: "fpsMode") == "fps120",
               "end-to-end migration copies missing legacy values")
        expect(defaults.object(forKey: "testPattern") == nil,
               "end-to-end migration drops debug-only values")
        ApplicationIdentityPolicy.migratePreferences(
            defaults: defaults,
            legacyDomainValues: [["transportMode": "usb"]])
        expect(defaults.object(forKey: "transportMode") == nil,
               "migration marker prevents a second migration")
        print("ApplicationIdentityPolicySelfTest PASS")
    }
}

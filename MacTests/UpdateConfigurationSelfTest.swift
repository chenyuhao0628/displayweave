import Foundation

@main
enum UpdateConfigurationSelfTest {
    static func main() throws {
        let source = try String(contentsOfFile: "project.yml", encoding: .utf8)

        expect(source.contains(
            "SUFeedURL: \(UpdateFeedPolicy.canonical)"
        ), "Sparkle feed must use the reachable migrated URL")
        expect(UpdateFeedPolicy.canonical != UpdateFeedPolicy.legacy,
               "old installations require a migration build")
        let delegate = try String(contentsOfFile: "Mac/UpdateViews.swift", encoding: .utf8)
        expect(delegate.contains("func feedURLString(for updater: SPUUpdater) -> String?"),
               "delegate overrides persisted legacy feed preferences")
        expect(delegate.contains("UpdateFeedPolicy.canonical"), "delegate selects managed feed")
        expect(source.contains("SUEnableAutomaticChecks: true"),
               "automatic update checks must be enabled")
        expect(source.contains("SUAutomaticallyUpdate: true"),
               "verified updates must be staged automatically")

        let marker = "SUPublicEDKey: "
        guard let range = source.range(of: marker) else {
            preconditionFailure("missing SUPublicEDKey")
        }
        let key = String(source[range.upperBound...].prefix { !$0.isNewline })
        expect(Data(base64Encoded: key)?.count == 32,
               "Sparkle public key must decode to 32 bytes")
        expect(key == "N9dMZV/F1ui58IsEmCv5jFVgDWiWv2yB/01KBlAHFjE=",
               "feed migration must preserve the shipped signing identity")

        print("UpdateConfigurationSelfTest PASS")
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() { fatalError(message) }
    }
}

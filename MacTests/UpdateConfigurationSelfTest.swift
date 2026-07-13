import Foundation

@main
enum UpdateConfigurationSelfTest {
    static func main() throws {
        let source = try String(contentsOfFile: "project.yml", encoding: .utf8)

        expect(source.contains(
            "SUFeedURL: https://chenyuhao0628.github.io/displayweave/appcast.xml"
        ), "Sparkle feed must use the published GitHub Pages URL")
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
        expect(key != "rYxlIePmwzi2bRo/qIsuY2TqTnQ34li2gQhJpGBiumw=",
               "obsolete Sparkle public key must be replaced")

        print("UpdateConfigurationSelfTest PASS")
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() { fatalError(message) }
    }
}

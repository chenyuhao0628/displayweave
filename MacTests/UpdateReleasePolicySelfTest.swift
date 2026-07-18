import Foundation

@main
enum UpdateReleasePolicySelfTest {
    static func main() throws {
        let gradle = try source("AndroidReceiver/app/build.gradle.kts")
        require(gradle.contains("environmentVariable(\"DISPLAYWEAVE_BUILD_NUMBER\")"),
                "Android build number is injectable")
        require(gradle.contains("environmentVariable(\"DISPLAYWEAVE_VERSION_NAME\")"),
                "Android version name is injectable")

        let package = try source("tools/package-preview-0.1.sh")
        for marker in [
            "DISPLAYWEAVE_VERSION_NAME", "DISPLAYWEAVE_BUILD_NUMBER",
            "DisplayWeave-macOS.zip", "DisplayWeave-Android.apk"
        ] {
            require(package.contains(marker), "package script requires \(marker)")
        }
        require(package.contains("MARKETING_VERSION=\"$VERSION_NAME\""),
                "Mac display version is injected")
        require(package.contains("CURRENT_PROJECT_VERSION=\"$BUILD_NUMBER\""),
                "Mac build number is injected")

        require(FileManager.default.isExecutableFile(
            atPath: "tools/generate-android-update-manifest.sh"),
                "Android feed generator is executable")
        require(FileManager.default.isExecutableFile(
            atPath: "tools/verify-update-release.sh"),
                "release verifier is executable")
        try verifyRejectionFixtures()
        print("UpdateReleasePolicySelfTest PASS")
    }

    private static func verifyRejectionFixtures() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("displayweave-feed-policy-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory,
                                                withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let apk = directory.appendingPathComponent("DisplayWeave-Android.apk")
        try Data("DisplayWeave update fixture\n".utf8).write(to: apk)
        let hash = "299de81054c36e6008cafe41f54125adfb815097fb1838dd7c1194c6b9189ee1"
        let certificate = "89805f045800ea18b56b84b32e8e31b1710a3c7bf3c85fda54d260d1fc6d589d"
        let valid = """
        {"schemaVersion":1,"packageName":"app.opendisplay.android","versionCode":123,
        "versionName":"0.2.0-preview.3","minimumSdk":26,
        "apkUrl":"https://downloads.urlget.cyou/releases/test/DisplayWeave-Android.apk",
        "apkFallbackUrl":"https://github.com/chenyuhao0628/displayweave/releases/download/test/DisplayWeave-Android.apk","apkSize":28,
        "sha256":"\(hash)","signingCertificateSha256":"\(certificate)",
        "publishedAt":"2026-07-14T00:00:00Z",
        "releaseNotesUrl":"https://github.com/example/releases/tag/test"}
        """
        let validStatus = try verify(valid, apk: apk, certificate: certificate)
        require(validStatus == 0,
                "valid Android feed fixture passes")
        for (label, invalid) in [
            ("HTTP URL", valid.replacingOccurrences(of: "https://downloads.urlget.cyou/releases/test/DisplayWeave",
                                                     with: "http://downloads.urlget.cyou/releases/test/DisplayWeave")),
            ("wrong fallback host", valid.replacingOccurrences(of: "https://github.com/chenyuhao0628",
                                                                with: "https://github.example/chenyuhao0628")),
            ("wrong size", valid.replacingOccurrences(of: "\"apkSize\":28", with: "\"apkSize\":29")),
            ("wrong hash", valid.replacingOccurrences(of: hash, with: String(repeating: "0", count: 64))),
            ("wrong fingerprint", valid.replacingOccurrences(of: certificate,
                                                               with: String(repeating: "1", count: 64)))
        ] {
            let invalidStatus = try verify(invalid, apk: apk, certificate: certificate)
            require(invalidStatus != 0,
                    "\(label) fixture is rejected")
        }
    }

    private static func verify(_ feed: String, apk: URL, certificate: String) throws -> Int32 {
        let feedURL = apk.deletingLastPathComponent().appendingPathComponent("feed.json")
        try feed.write(to: feedURL, atomically: true, encoding: .utf8)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["tools/verify-update-release.sh", "--android-metadata",
                             feedURL.path, apk.path, "0.2.0-preview.3", "123", certificate]
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        try process.run()
        process.waitUntilExit()
        return process.terminationStatus
    }

    private static func source(_ path: String) throws -> String {
        try String(contentsOfFile: path, encoding: .utf8)
    }

    private static func require(_ condition: @autoclosure () -> Bool, _ message: String) {
        precondition(condition(), message)
    }
}

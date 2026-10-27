#!/usr/bin/env python3
"""Exercise the collector's actual preference snapshot with an isolated domain."""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
source = (root / "tools/collect-mac-display-evidence.swift").read_text()
begin = source.index("func preferenceSnapshot(_ id: String) -> [String: Any] {")
end = source.index("// Window bounds are outer-window geometry", begin)
fixture = r'''
import Foundation
import CoreFoundation
import CryptoKit
''' + source[begin:end] + r'''

@main struct CollectorPreferenceRegression {
    struct Failure: Error { let message: String }
    static func main() throws {
        let domain = "app.displayweave.collector-test." + UUID().uuidString
        let mapKey = "desktopResolutions.v1" as CFString
        let defaultKey = "desktopResolutionDefault.v2" as CFString
        let privateKey = "privateTrustToken" as CFString
        defer {
            CFPreferencesSetAppValue(mapKey, nil, domain as CFString)
            CFPreferencesSetAppValue(defaultKey, nil, domain as CFString)
            CFPreferencesSetAppValue(privateKey, nil, domain as CFString)
            CFPreferencesAppSynchronize(domain as CFString)
        }
        func values() -> [String: Any] {
            preferenceSnapshot(domain)["storedValuesOnly"] as! [String: Any]
        }
        func alias(_ peer: String) -> String {
            "peer-" + SHA256.hash(data: Data(peer.utf8)).prefix(6)
                .map { String(format: "%02x", $0) }.joined()
        }
        func check(_ condition: @autoclosure () -> Bool, _ message: String) throws {
            if !condition() { throw Failure(message: message) }
        }
        try check(values()["desktopResolutionDefault.v2"] == nil, "missing default was inferred")
        let saved = ["private-auto-peer": "automatic", "private-old-peer": "iMac4K",
                     "private-future-peer": "future-value"]
        CFPreferencesSetAppValue(mapKey, saved as CFDictionary, domain as CFString)
        CFPreferencesSetAppValue(defaultKey, "automatic" as CFString, domain as CFString)
        CFPreferencesSetAppValue(privateKey, "must-not-export" as CFString, domain as CFString)
        let snapshot = values()
        try check(snapshot["desktopResolutionDefault.v2"] as? String == "automatic", "automatic default missing")
        try check(snapshot["privateTrustToken"] == nil, "private preference was exported")
        let peers = snapshot["desktopResolutions.v1"] as! [[String: String]]
        let resolutions = Dictionary(uniqueKeysWithValues: peers.map { ($0["peerAlias"]!, $0["resolution"]!) })
        try check(resolutions[alias("private-auto-peer")] == "automatic", "automatic peer not recognized")
        try check(resolutions[alias("private-old-peer")] == "iMac4K", "legacy peer not recognized")
        try check(resolutions[alias("private-future-peer")] == "unknown", "unknown peer value exported")
        try check(!String(describing: peers).contains("private-"), "raw peer identity exported")

        CFPreferencesSetAppValue(defaultKey, "future-value" as CFString, domain as CFString)
        try check(values()["desktopResolutionDefault.v2"] as? String == "unknown", "unknown default exported")
        CFPreferencesSetAppValue(defaultKey, "native" as CFString, domain as CFString)
        try check(values()["desktopResolutionDefault.v2"] as? String == "native", "native default missing")
        CFPreferencesSetAppValue(defaultKey, nil, domain as CFString)
        try check(values()["desktopResolutionDefault.v2"] == nil, "removed default was inferred")

        let many = Dictionary(uniqueKeysWithValues: (0..<130).map {
            (String(format: "peer-%03d", $0), "automatic")
        })
        CFPreferencesSetAppValue(mapKey, many as CFDictionary, domain as CFString)
        let bounded = values()["desktopResolutions.v1"] as! [[String: String]]
        try check(bounded.count == 128, "peer export was not bounded")
        try check(bounded.last?["peerAlias"] == alias("peer-127"), "peer selection was not deterministic")
        print("Collector preference snapshot PASS: automatic/default, unknown, privacy and bounds")
    }
}
'''
with tempfile.TemporaryDirectory(prefix="displayweave-collector-test-") as temporary:
    path = Path(temporary)
    (path / "Fixture.swift").write_text(fixture)
    subprocess.run(["swiftc", "-parse-as-library", str(path / "Fixture.swift"), "-o", str(path / "test")],
                   cwd=root, check=True)
    subprocess.run([str(path / "test")], check=True, timeout=30)

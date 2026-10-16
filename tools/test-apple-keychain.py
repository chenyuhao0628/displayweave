#!/usr/bin/env python3
"""Exercise real app-scoped Keychain persistence in disposable test identities.

No installed DisplayWeave app or identity is read, launched or replaced. The
optional iOS run creates and deletes its own simulator and tiny test app.
"""
import argparse
import json
import pathlib
import subprocess
import tempfile
import time

ROOT = pathlib.Path(__file__).resolve().parents[1]
SOURCES = ["Shared/AppleTransportIdentity.swift", "Shared/SecurePairingProtocol.swift",
           "Shared/SecurePairingState.swift", "Shared/AppleSecurityStore.swift",
           "MacTests/AppleSecurityStoreSelfTest.swift"]


def run(args, timeout=90):
    result = subprocess.run(args, cwd=ROOT, text=True, stdout=subprocess.PIPE,
                            stderr=subprocess.STDOUT, timeout=timeout)
    if result.returncode:
        raise RuntimeError(result.stdout[-10000:])
    return result.stdout


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--ios-simulator", action="store_true")
    args = parser.parse_args()
    with tempfile.TemporaryDirectory(prefix="displayweave-keychain-") as folder:
        folder = pathlib.Path(folder)
        executable = folder / "KeychainTest"
        run(["xcrun", "swiftc", *SOURCES, "-o", str(executable)])
        run(["codesign", "--force", "--sign", "-", str(executable)])
        output = run([str(executable)])
        assert "PASS" in output, output
        print("macOS " + output.strip(), flush=True)
        if not args.ios_simulator:
            return
        runtimes = json.loads(run(["xcrun", "simctl", "list", "runtimes", "-j"]))["runtimes"]
        runtime = next(r for r in runtimes if r.get("isAvailable") and r.get("platform") == "iOS")
        types = runtime["supportedDeviceTypes"]
        device_type = next(t["identifier"] for t in types if t["productFamily"] == "iPhone")
        bundle_id = "app.displayweave.keychain-self-test"
        # Let Xcode generate the simulator's signing/entitlement sections. A
        # hand-signed CLI binary lacks that app context and returns -34018.
        spec = folder / "project.json"
        spec.write_text(json.dumps({"name": "KeychainTest", "targets": {"KeychainTest": {
            "type": "application", "platform": "iOS", "deploymentTarget": "17.0",
            "sources": [str(ROOT / source) for source in SOURCES],
            "settings": {"base": {"PRODUCT_BUNDLE_IDENTIFIER": bundle_id, "SWIFT_VERSION": "5.9",
                                   "GENERATE_INFOPLIST_FILE": "YES", "CODE_SIGN_STYLE": "Automatic"}}
        }}}))
        run(["xcodegen", "generate", "--spec", str(spec), "--project", str(folder)])
        derived = folder / "Derived"
        run(["xcodebuild", "-quiet", "-project", str(folder / "KeychainTest.xcodeproj"),
             "-scheme", "KeychainTest", "-configuration", "Debug", "-sdk", "iphonesimulator",
             "-destination", "generic/platform=iOS Simulator", "-derivedDataPath", str(derived),
             "CODE_SIGNING_ALLOWED=YES", "CODE_SIGN_IDENTITY=-", "DEVELOPMENT_TEAM=", "build"], timeout=180)
        app = derived / "Build/Products/Debug-iphonesimulator/KeychainTest.app"
        simulator = run(["xcrun", "simctl", "create", "DisplayWeave Keychain Test", device_type,
                         runtime["identifier"]]).strip()
        try:
            run(["xcrun", "simctl", "boot", simulator])
            run(["xcrun", "simctl", "bootstatus", simulator, "-b"], timeout=180)
            run(["xcrun", "simctl", "install", simulator, str(app)])
            run(["xcrun", "simctl", "launch", simulator, bundle_id], timeout=30)
            container = pathlib.Path(run(["xcrun", "simctl", "get_app_container", simulator, bundle_id, "data"]).strip())
            result = container / "Documents/keychain-test-result.txt"
            deadline = time.monotonic() + 20
            while not result.exists():
                if time.monotonic() >= deadline:
                    raise RuntimeError("iOS Keychain test did not finish")
                time.sleep(0.1)
            output = result.read_text()
            assert "Apple Keychain:" in output and output.endswith("PASS"), output
            print("iOS Simulator " + output, flush=True)
        finally:
            subprocess.run(["xcrun", "simctl", "shutdown", simulator], capture_output=True, timeout=30)
            run(["xcrun", "simctl", "delete", simulator])


if __name__ == "__main__":
    main()

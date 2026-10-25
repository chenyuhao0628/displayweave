#!/usr/bin/env python3
"""Real PhoneReceiver TLS smoke in a disposable simulator; no desktop capture."""
import argparse
import json
import pathlib
import runpy
import socket
import subprocess
import tempfile
import time

helpers = runpy.run_path(str(pathlib.Path(__file__).with_name("test-apple-keychain.py")))
run, ROOT = helpers["run"], helpers["ROOT"]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--screenshots", type=pathlib.Path, help="Optional local UI evidence after the invitation is consumed")
    args = parser.parse_args()
    with tempfile.TemporaryDirectory(prefix="displayweave-secure-phone-") as temporary:
        folder = pathlib.Path(temporary)
        sources = sorted(str(path) for path in (ROOT / "Shared").glob("*.swift"))
        sources += [str(ROOT / path) for path in ["iOS/PhoneReceiver.swift", "iOS/ReceiverSceneLifecyclePolicy.swift",
                                                 "iOS/Log.swift", "iOS/ReceiverIdleView.swift", "iOS/ReceiverOnboardingView.swift", "iOS/ReceiverSettingsView.swift", "iOS/PencilSettings.swift", "iOS/ReceiverVideoView.swift", "iOS/TouchPressPolicy.swift", "iOS/MetalVideoRenderer.swift", "MacTests/SecurePhoneReceiverFixture.swift"]]
        sources.append(str(ROOT / "iOS/Assets.xcassets"))
        bundle_id = "app.displayweave.secure-phone-self-test"
        spec = folder / "project.json"
        spec.write_text(json.dumps({"name": "PhoneTest", "targets": {"PhoneTest": {
            "type": "application", "platform": "iOS", "deploymentTarget": "17.0", "sources": sources,
            "info": {"path": "Info.plist", "properties": {"NSLocalNetworkUsageDescription": "Isolated local TLS test",
                "NSBonjourServices": ["_opensidecar._tcp"], "UILaunchScreen": {}}},
            "settings": {"base": {"PRODUCT_BUNDLE_IDENTIFIER": bundle_id, "SWIFT_VERSION": "5.9", "CODE_SIGN_STYLE": "Automatic"}}
        }}}))
        run(["xcodegen", "generate", "--spec", str(spec), "--project", str(folder)])
        derived = folder / "Derived"
        run(["xcodebuild", "-quiet", "-project", str(folder / "PhoneTest.xcodeproj"), "-scheme", "PhoneTest",
             "-configuration", "Debug", "-sdk", "iphonesimulator", "-destination", "generic/platform=iOS Simulator",
             "-derivedDataPath", str(derived), "CODE_SIGNING_ALLOWED=YES", "CODE_SIGN_IDENTITY=-", "DEVELOPMENT_TEAM=", "build"], timeout=180)
        client = folder / "PhoneClient"
        client_sources = [*helpers["SOURCES"][:-1], "Shared/AppleTLS.swift", "Shared/AppleSecureAdmission.swift",
            "Shared/AppleTransportSecurity.swift", "Shared/ReceiverFrameDecoder.swift", "Shared/ReceiverCursorImage.swift",
            "Shared/ReceiverVideoBitstream.swift", "Shared/AppleVideoPolicy.swift", "Mac/EncoderHardwareCapabilities.swift",
            "Shared/DesktopInputProtocol.swift", "Shared/InputSendBudget.swift", "Shared/PencilProtocol.swift", "Shared/PencilActions.swift",
            "Mac/Receiver/ReceiverWireProtocol.swift", "Mac/LatestValueRelay.swift", "Shared/ReceiverVideoFlowPolicy.swift", "Mac/Receiver/MacVideoRenderer.swift", "Mac/Receiver/StreamReceiver.swift", "MacTests/ReceiverTestSupport.swift",
            "MacTests/MacSecureReceiverSelfTest.swift"]
        run(["xcrun", "swiftc", *client_sources, "-o", str(client)])
        runtimes = json.loads(run(["xcrun", "simctl", "list", "runtimes", "-j"]))["runtimes"]
        runtime = next(r for r in runtimes if r.get("isAvailable") and r.get("platform") == "iOS")
        device_type = next(t["identifier"] for t in runtime["supportedDeviceTypes"] if t["productFamily"] == "iPhone")
        simulator = run(["xcrun", "simctl", "create", "DisplayWeave TLS Test", device_type, runtime["identifier"]]).strip()
        with socket.socket() as reservation:
            reservation.bind(("127.0.0.1", 0))
            port = reservation.getsockname()[1]
        try:
            run(["xcrun", "simctl", "boot", simulator])
            run(["xcrun", "simctl", "bootstatus", simulator, "-b"], timeout=180)
            run(["xcrun", "simctl", "install", simulator, str(derived / "Build/Products/Debug-iphonesimulator/PhoneTest.app")])
            run(["xcrun", "simctl", "launch", simulator, bundle_id, "-testPort", str(port)])
            container = pathlib.Path(run(["xcrun", "simctl", "get_app_container", simulator, bundle_id, "data"]).strip())
            documents = container / "Documents"
            deadline = time.monotonic() + 15
            while not (documents / "invitation.txt").exists():
                if (documents / "error.txt").exists():
                    raise RuntimeError((documents / "error.txt").read_text())
                if time.monotonic() >= deadline:
                    raise RuntimeError("simulator fixture did not open pairing")
                time.sleep(0.1)
            print((documents / "presentation-result.txt").read_text(), flush=True)
            print(run([str(client), "--ios-fixture", str(documents), str(port)], timeout=55).strip(), flush=True)
            if args.screenshots:
                args.screenshots.mkdir(parents=True, exist_ok=True)
                for appearance in ("light", "dark"):
                    run(["xcrun", "simctl", "ui", simulator, "appearance", appearance])
                    time.sleep(0.5)
                    run(["xcrun", "simctl", "io", simulator, "screenshot", str(args.screenshots / (appearance + ".png"))])
                for surface in ("idle", "onboarding", "settings"):
                    (documents / "command.txt").write_text("ui-" + surface)
                    time.sleep(0.5)
                    for appearance in ("light", "dark"):
                        run(["xcrun", "simctl", "ui", simulator, "appearance", appearance])
                        time.sleep(0.5)
                        run(["xcrun", "simctl", "io", simulator, "screenshot", str(args.screenshots / (surface + "-" + appearance + ".png"))])
                (documents / "command.txt").write_text("ui-idle")
                run(["xcrun", "simctl", "ui", simulator, "content_size", "accessibility-extra-extra-extra-large"])
                time.sleep(0.5)
                run(["xcrun", "simctl", "io", simulator, "screenshot", str(args.screenshots / "idle-accessibility.png")])
                print("iOS production waiting/onboarding/settings light-dark and large-text captures complete", flush=True)
            run(["xcrun", "simctl", "launch", simulator, "com.apple.Preferences"])
            deadline = time.monotonic() + 10
            while True:
                try:
                    with socket.create_connection(("127.0.0.1", port), timeout=0.5):
                        pass
                except OSError:
                    print("iOS background listener shutdown PASS", flush=True)
                    break
                if time.monotonic() >= deadline:
                    phase = (documents / "phase.txt").read_text() if (documents / "phase.txt").exists() else "missing"
                    raise RuntimeError("receiver still listening after app switch; scene phase=" + phase)
                time.sleep(0.1)
        finally:
            subprocess.run(["xcrun", "simctl", "shutdown", simulator], capture_output=True, timeout=30)
            run(["xcrun", "simctl", "delete", simulator])


if __name__ == "__main__":
    main()

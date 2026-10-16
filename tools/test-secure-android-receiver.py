#!/usr/bin/env python3
"""Real Android Keystore + Apple TLS admission in a disposable AVD and test package.

Requires an installed ARM64 Android 35 default system image and SDK command-line
 tools. Production APKs contain none of the invitation-export/test activity code.
"""
import argparse
import base64
import json
import struct
import os
import pathlib
import re
import shutil
import socket
import subprocess
import tempfile
import time
import xml.etree.ElementTree as ET

ROOT = pathlib.Path(__file__).resolve().parents[1]
PACKAGE = "app.displayweave.securitytest"


def run(args, *, cwd=ROOT, env=None, timeout=90, data=None):
    result = subprocess.run([str(arg) for arg in args], cwd=cwd, env=env, input=data,
                            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=timeout)
    if result.returncode:
        raise RuntimeError(result.stdout.decode(errors="replace")[-8000:])
    return result.stdout


def wait_until(predicate, description, timeout=45):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        result = predicate()
        if result:
            return result
        time.sleep(0.3)
    raise RuntimeError("Timed out: " + description)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--screenshots", type=pathlib.Path)
    args = parser.parse_args()
    sdk = pathlib.Path(os.environ.get("ANDROID_SDK_ROOT", str(pathlib.Path.home() / "Library/Android/sdk")))
    image = "system-images;android-35;default;arm64-v8a"
    if not (sdk / "system-images/android-35/default/arm64-v8a/system.img").exists():
        raise RuntimeError("Install " + image + " with sdkmanager first")
    adb = sdk / "platform-tools/adb"
    with tempfile.TemporaryDirectory(prefix="displayweave-android-security-") as temporary:
        folder = pathlib.Path(temporary)
        project = folder / "AndroidReceiver"
        shutil.copytree(ROOT / "AndroidReceiver", project,
                        ignore=shutil.ignore_patterns("build", ".gradle", "local.properties"))
        (project / "local.properties").write_text("sdk.dir=" + str(sdk) + "\n")
        build = project / "app/build.gradle.kts"
        build.write_text(build.read_text().replace('applicationId = "app.opendisplay.android"',
                                                   'applicationId = "' + PACKAGE + '"'))
        manifest = project / "app/src/main/AndroidManifest.xml"
        manifest.write_text(manifest.read_text().replace("app.opendisplay.android.update-files", PACKAGE + ".update-files"))
        debug = project / "app/src/debug"
        source = debug / "java/app/opendisplay/android"
        source.mkdir(parents=True)
        for original in (ROOT / "AndroidReceiver/tests/runtime/SecurityRuntimeTestActivity.java",
                         ROOT / "AndroidReceiver/tests/java/app/opendisplay/android/SecureTransportSelfTest.java"):
            shutil.copy(original, source / original.name)
        (debug / "AndroidManifest.xml").write_text('''<manifest xmlns:android="http://schemas.android.com/apk/res/android">
<application><activity android:name="app.opendisplay.android.SecurityRuntimeTestActivity" android:exported="true" android:configChanges="keyboardHidden|orientation|screenSize" /></application></manifest>''')
        run([project / "gradlew", "--no-daemon", "assembleDebug"], cwd=project, timeout=180)
        client = folder / "android-client"
        sources = ["AppleTransportIdentity", "AppleTLS", "AppleSecureAdmission", "SecurePairingProtocol",
                   "SecurePairingState", "ReceiverFrameDecoder"]
        run(["xcrun", "swiftc", *[ROOT / ("Shared/" + name + ".swift") for name in sources],
             ROOT / "MacTests/SecureAndroidReceiverClient.swift", "-o", client])
        env = os.environ.copy()
        env["ANDROID_AVD_HOME"] = str(folder / "avds")
        pathlib.Path(env["ANDROID_AVD_HOME"]).mkdir()
        run([sdk / "cmdline-tools/latest/bin/avdmanager", "create", "avd", "--name", "DisplayWeaveSecurityTest",
             "--package", image, "--device", "pixel_5"], env=env, data=b"no\n")
        # Select a free emulator console/adb pair; no existing emulator is touched.
        console_port = None
        for candidate in range(5580, 5680, 2):
            with socket.socket() as one, socket.socket() as two:
                try:
                    one.bind(("127.0.0.1", candidate)); two.bind(("127.0.0.1", candidate + 1))
                    console_port = candidate; break
                except OSError:
                    continue
        if console_port is None:
            raise RuntimeError("No free emulator port pair")
        serial = "emulator-" + str(console_port)
        def device(*arguments, **kwargs):
            return run([adb, "-s", serial, *arguments], **kwargs)
        def private(name):
            result = subprocess.run([str(adb), "-s", serial, "shell", "-T", "run-as", PACKAGE, "cat", "files/" + name],
                                    stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, timeout=10)
            return result.stdout if result.returncode == 0 else None
        def result(name):
            error = private("error.txt")
            if error:
                raise RuntimeError(error.decode())
            return private(name)
        emulator_log = open(folder / "emulator.log", "wb")
        emulator = subprocess.Popen([str(sdk / "emulator/emulator"), "-avd", "DisplayWeaveSecurityTest",
                                     "-port", str(console_port), "-no-window", "-no-audio", "-no-snapshot",
                                     "-gpu", "swiftshader_indirect"], env=env, stdout=emulator_log, stderr=subprocess.STDOUT)
        client_process = None
        forwarded = None
        try:
            def booted():
                if emulator.poll() is not None:
                    raise RuntimeError((folder / "emulator.log").read_text()[-5000:])
                response = subprocess.run([str(adb), "-s", serial, "shell", "getprop", "sys.boot_completed"],
                                          capture_output=True, timeout=10)
                return response.returncode == 0 and response.stdout.strip() == b"1"
            wait_until(booted, "Android boot", timeout=180)
            device("shell", "input", "keyevent", "82")
            device("shell", "cmd", "uimode", "night", "no")
            device("install", "-g", project / "app/build/outputs/apk/debug/app-debug.apk")
            activity = PACKAGE + "/app.opendisplay.android.SecurityRuntimeTestActivity"
            device("shell", "am", "start", "-n", activity)
            print(wait_until(lambda: result("result.txt"), "Keystore runtime suite", 60).decode(), flush=True)
            device("shell", "am", "force-stop", PACKAGE)
            device("shell", "am", "start", "-n", activity, "--es", "mode", "reload")
            print(wait_until(lambda: result("reload-result.txt"), "process persistence", 30).decode(), flush=True)
            (folder / "server.der").write_bytes(base64.b64decode(private("certificate.txt")))
            forwarded = device("forward", "tcp:0", "tcp:9000").decode().strip()
            def tree():
                diagnostic = ""
                for _ in range(3):
                    diagnostic = device("shell", "uiautomator", "dump", "/sdcard/security-ui.xml", timeout=30).decode(errors="replace")
                    if "dumped" in diagnostic:
                        data = device("exec-out", "cat", "/sdcard/security-ui.xml").decode(errors="replace")
                        if "<?xml" in data and "</hierarchy>" in data:
                            return ET.fromstring(data[data.index("<?xml"):data.index("</hierarchy>") + len("</hierarchy>")])
                    time.sleep(0.5)
                raise RuntimeError("UI tree unavailable: " + diagnostic)
            def tap(text, optional=False):
                for attempt in range(4):
                    nodes = list(tree().iter("node"))
                    found = next((node for node in nodes if node.get("text") == text), None)
                    if found is not None:
                        bounds = [int(value) for value in re.findall(r"\d+", found.get("bounds", ""))]
                        if len(bounds) == 4 and bounds[3] > bounds[1]:
                            device("shell", "input", "tap", str((bounds[0]+bounds[2])//2), str((bounds[1]+bounds[3])//2)); return True
                    scroll = next((node for node in nodes if node.get("scrollable") == "true"), None)
                    if scroll is not None:
                        x1,y1,x2,y2 = [int(value) for value in re.findall(r"\d+", scroll.get("bounds"))]
                        device("shell", "input", "swipe", str((x1+x2)//2), str(y2-100), str((x1+x2)//2), str(y1+100), "300")
                    elif optional:
                        return False
                    time.sleep(0.3)
                if optional:
                    return False
                visible = [node.get("text", "") + " [" + node.get("resource-id", "") + "]" for node in nodes
                           if not node.get("text", "").startswith("DW1.")]
                diagnostic = device("logcat", "-d", "-s", "DisplayWeave:W", "AndroidRuntime:E", "*:S", timeout=15).decode(errors="replace")
                raise RuntimeError("UI item missing: " + text + "; visible=" + repr(visible)[-2500:] + diagnostic[-5000:])
            tap("知道了", optional=True)
            # MainActivity owns the real listener; wait only for TCP availability.
            # The Swift client still independently requires pinned TLS and ready/hello.
            def listening():
                try:
                    with socket.create_connection(("127.0.0.1", int(forwarded)), timeout=0.5) as probe:
                        probe.settimeout(0.2)
                        try:
                            return probe.recv(1) != b""
                        except socket.timeout:
                            return True
                except OSError:
                    return False
            wait_until(listening, "production listener")
            if args.screenshots:
                args.screenshots.mkdir(parents=True, exist_ok=True)
                (args.screenshots / "android-idle-light.png").write_bytes(device("exec-out", "screencap", "-p"))
            tap("配对与连接设置")
            tap("安全与配对")
            tap("生成接收邀请")
            invitation = next(node.get("text") for node in tree().iter("node") if node.get("text", "").startswith("DW1."))
            (folder / "invitation.txt").write_text(invitation)
            (folder / "invitation.txt").chmod(0o600)
            client_log = open(folder / "client.log", "wb")
            client_process = subprocess.Popen([str(client), str(folder), forwarded], stdout=client_log, stderr=subprocess.STDOUT)
            def connected():
                if client_process.poll() is not None:
                    diagnostics = device("logcat", "-d", "-s", "DisplayWeave:W", "AndroidRuntime:E", "*:S", timeout=15).decode(errors="replace")
                    raise RuntimeError((folder / "client.log").read_text()[-3000:] + diagnostics[-5000:])
                return (folder / "ready.txt").exists()
            wait_until(connected, "Apple/Android admission and application pong", 25)
            time.sleep(0.6)  # invitation UI observes one-use consumption
            if args.screenshots:
                args.screenshots.mkdir(parents=True, exist_ok=True)
                (args.screenshots / "android-security-light.png").write_bytes(device("exec-out", "screencap", "-p"))
            tap("撤销 “Fixture Mac”")
            if client_process.wait(timeout=15) != 0:
                raise RuntimeError((folder / "client.log").read_text()[-5000:])
            print((folder / "client.log").read_text().strip(), flush=True)
            tap("允许旧版明文接收（不安全）")
            tap("启用明文兼容")
            def legacy_hello():
                try:
                    with socket.create_connection(("127.0.0.1", int(forwarded)), timeout=1) as probe:
                        probe.settimeout(1)
                        header = probe.recv(4, socket.MSG_WAITALL)
                        if len(header) != 4:
                            return False
                        size = struct.unpack("!I", header)[0]
                        if not 0 < size <= 65536:
                            return False
                        body = probe.recv(size, socket.MSG_WAITALL)
                        return json.loads(body).get("type") == "hello"
                except (OSError, ValueError):
                    return False
            wait_until(legacy_hello, "explicit legacy listener restart", 10)
            tap("允许旧版明文接收（不安全）")
            time.sleep(0.5)
            if legacy_hello():
                raise RuntimeError("disabling legacy left a plaintext listener")
            print("Android explicit legacy enable/disable through Settings PASS", flush=True)
            if args.screenshots:
                device("shell", "cmd", "uimode", "night", "yes")
                time.sleep(0.5)
                tap("配对与连接设置")
                tap("安全与配对")
                wait_until(lambda: any(node.get("resource-id") == "android:id/alertTitle" and node.get("text") == "安全与配对"
                                       for node in tree().iter("node")), "dark security settings rendering", 10)
                (args.screenshots / "android-security-dark.png").write_bytes(device("exec-out", "screencap", "-p"))
                device("shell", "input", "keyevent", "4")
                device("shell", "input", "keyevent", "4")
                tree()  # wait for dialog dismissal/animation before capturing idle UI
                (args.screenshots / "android-idle-dark.png").write_bytes(device("exec-out", "screencap", "-p"))
                tap("连接客户端：DisplayWeave 加密")
                tap("OpenDisplay 兼容（未加密）")
                tap("启用明文兼容")
                wait_until(legacy_hello, "main-screen OpenDisplay entry", 10)
                tap("允许旧版明文接收（不安全）")
                wait_until(lambda: listening() and not legacy_hello(), "main-screen secure listener restoration", 10)
                print("Android main-screen OpenDisplay mode and secure restoration PASS", flush=True)

            device("shell", "input", "keyevent", "3")
            def stopped():
                try:
                    with socket.create_connection(("127.0.0.1", int(forwarded)), timeout=0.5) as probe:
                        probe.settimeout(0.5)
                        return probe.recv(1) == b""
                except OSError:
                    return True
            wait_until(stopped, "Android background listener close", 10)
            print("Android background listener shutdown PASS", flush=True)
            diagnostics = device("logcat", "-d", "-s", "DisplayWeave:W", "AndroidRuntime:E", "*:S", timeout=15).decode(errors="replace")
            if "Local security settings operation failed" in diagnostics or "FATAL EXCEPTION" in diagnostics:
                raise RuntimeError("Runtime UI error: " + diagnostics[-5000:])
        finally:
            if client_process and client_process.poll() is None:
                client_process.kill(); client_process.wait()
            if forwarded:
                subprocess.run([str(adb), "-s", serial, "forward", "--remove", "tcp:" + forwarded], capture_output=True, timeout=10)
            subprocess.run([str(adb), "-s", serial, "emu", "kill"], capture_output=True, timeout=10)
            try:
                emulator.wait(timeout=20)
            except subprocess.TimeoutExpired:
                emulator.terminate(); emulator.wait(timeout=10)
            emulator_log.close()


if __name__ == "__main__":
    main()

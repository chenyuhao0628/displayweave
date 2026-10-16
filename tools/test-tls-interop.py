#!/usr/bin/env python3
"""Exercise production TLS helpers through Apple Network.framework and JVM JSSE.

All private test keys are generated into a disposable temporary directory. No
application Keychain/Keystore entries, installed apps or release keys are used.
"""
import pathlib
import subprocess
import tempfile
import time

ROOT = pathlib.Path(__file__).resolve().parents[1]


def run(*args):
    subprocess.run([str(arg) for arg in args], cwd=ROOT, check=True, timeout=45)


def wait_file(path, process):
    deadline = time.monotonic() + 10
    while not path.exists():
        if process.poll() is not None or time.monotonic() > deadline:
            raise RuntimeError("TLS fixture did not become ready")
        time.sleep(0.05)


def finish(process):
    if process.wait(timeout=25) != 0:
        raise RuntimeError("TLS fixture failed")


def main():
    with tempfile.TemporaryDirectory(prefix="displayweave-tls-") as temp:
        folder = pathlib.Path(temp)
        swift = folder / "tls-test"
        run("swiftc", "Shared/AppleTransportIdentity.swift", "Shared/AppleTLS.swift",
            "MacTests/SecureTLSNetworkSelfTest.swift", "-o", swift)
        run(swift)
        run("javac", "-d", folder,
            "AndroidReceiver/app/src/main/java/app/opendisplay/android/SecureTls.java",
            "AndroidReceiver/app/src/main/java/app/opendisplay/android/TransportCertificate.java",
            "AndroidReceiver/tests/java/app/opendisplay/android/SecureTlsInteropSelfTest.java")
        store, cert = folder / "identity.p12", folder / "identity.der"
        run("keytool", "-genkeypair", "-alias", "transport", "-keyalg", "EC", "-groupname", "secp256r1",
            "-dname", "CN=DisplayWeave TLS test", "-validity", "365",
            "-storetype", "PKCS12", "-keystore", store,
            "-storepass", "fixture-password", "-noprompt")
        run("java", "-cp", folder, "app.opendisplay.android.SecureTlsInteropSelfTest", "prepare", store, cert)
        ready = folder / "swift-ready"
        server = subprocess.Popen([str(swift), "--java-peer", str(cert), str(ready)], cwd=ROOT)
        try:
            wait_file(ready, server)
            port, fingerprint = ready.read_text().splitlines()
            run("java", "-cp", folder, "app.opendisplay.android.SecureTlsInteropSelfTest",
                "client", store, port, fingerprint)
            finish(server)
        finally:
            if server.poll() is None:
                server.kill()
                server.wait()
        client_cert, ready = folder / "swift-client.der", folder / "java-ready"
        client = subprocess.Popen([str(swift), "--java-server", str(cert), str(client_cert), str(ready)], cwd=ROOT)
        try:
            wait_file(client_cert, client)
            run("java", "-cp", folder, "app.opendisplay.android.SecureTlsInteropSelfTest",
                "server", store, client_cert, ready)
            finish(client)
        finally:
            if client.poll() is None:
                client.kill()
                client.wait()
    print("Apple ↔ Java TLS interoperability PASS (ephemeral identities only)")


if __name__ == "__main__":
    main()

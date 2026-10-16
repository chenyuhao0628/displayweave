#!/usr/bin/env python3
"""Two real signed binaries retain production Keychain identity and pairing.

No TCC permissions, installed app, or user pairing records are modified.
Requires the locally configured Apple signing identity. Temporary files and
the random test Keychain namespace are removed even when verification fails.
"""
import hashlib
from pathlib import Path
import tempfile
import uuid

import mac_signing as signing

SOURCES = ["Shared/AppleTransportIdentity.swift", "Shared/SecurePairingProtocol.swift",
           "Shared/SecurePairingState.swift", "Shared/AppleSecurityStore.swift",
           "MacTests/SigningUpgradeSelfTest.swift"]


def main():
    policy = signing.load_policy()
    with tempfile.TemporaryDirectory(prefix="displayweave-signed-upgrade-") as folder:
        folder = Path(folder)
        scope = "app.displayweave.signing-test." + str(uuid.uuid4())
        binaries = [folder / "first", folder / "second"]
        for index, binary in enumerate(binaries):
            signing.run(["xcrun", "swiftc", *[signing.ROOT / p for p in SOURCES],
                         *(["-D", "FIRST_SIGNED_BUILD"] if index == 0 else []), "-o", binary], timeout=180)
            signing.run(["codesign", "--force", "--sign", policy["identitySHA1"], "--identifier", scope,
                         "--options", "runtime", "--timestamp", binary])
        assert hashlib.sha256(binaries[0].read_bytes()).digest() != hashlib.sha256(binaries[1].read_bytes()).digest()
        first, second = [signing.code_details(binary) for binary in binaries]
        assert first["requirement"] == second["requirement"] and not first["adHoc"] and not second["adHoc"]
        for binary in binaries:
            signing.run(["codesign", "--verify", "--strict", "-R=" + first["requirement"], binary])
        record = folder / "fixture.json"
        try:
            for binary, phase in ((binaries[0], "seed"), (binaries[1], "check")):
                result = signing.run([binary, phase, scope, record], timeout=60)
                print(result.stdout.decode().strip(), flush=True)
            print("Different signed builds: designated requirement, Keychain identity and pairing continuity PASS", flush=True)
        finally:
            print(signing.run([binaries[0], "cleanup", scope, record], timeout=30).stdout.decode().strip())
    print("Privacy permission continuity still needs an interactive upgrade acceptance; this test does not grant or simulate TCC access.")


if __name__ == "__main__":
    main()

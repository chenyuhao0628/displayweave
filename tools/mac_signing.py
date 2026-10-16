#!/usr/bin/env python3
"""Pinned macOS preview/development signing. Never creates or exports a key."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
IDS = {"Release": "app.displayweave.mac", "Debug": "app.displayweave.mac.debug"}
FEED = "https://chenyuhao0628.github.io/displayweave/appcast.xml"
UPDATE_KEY = "N9dMZV/F1ui58IsEmCv5jFVgDWiWv2yB/01KBlAHFjE="
PROBE_ID = "app.displayweave.signing-probe"


class SigningError(Exception):
    pass


def require(condition, message):
    if not condition:
        raise SigningError(message)


def run(args, *, input=None, timeout=120):
    try:
        result = subprocess.run([str(a) for a in args], input=input, stdout=subprocess.PIPE,
                                stderr=subprocess.PIPE, timeout=timeout, check=False)
    except (OSError, subprocess.TimeoutExpired) as error:
        raise SigningError(f"{args[0]} could not complete: {error}") from error
    require(result.returncode == 0,
            f"{args[0]} failed: {result.stderr.decode(errors='replace')[-4000:]}")
    return result


def config_path():
    return Path(os.environ.get("DISPLAYWEAVE_MAC_SIGNING_CONFIG",
                str(Path.home() / "Library/Application Support/DisplayWeave/Signing/mac-signing.json")))


def select_identity(output, digest):
    require(bool(re.fullmatch(r"[0-9A-Fa-f]{40}", digest)),
            "Select an existing Apple certificate by its 40-digit SHA-1; ad-hoc signing is not allowed.")
    for fingerprint, name in re.findall(r'^\s*\d+\)\s+([0-9A-Fa-f]{40})\s+"([^"]+)"\s*$', output, re.M):
        if fingerprint.upper() == digest.upper():
            require(name.startswith(("Apple Development:", "Developer ID Application:")),
                    "Use an Apple-issued Mac identity; local self-signed identities are not supported.")
            return name
    raise SigningError("The pinned signing identity/private key is unavailable. Restore it in Keychain; do not fall back to ad-hoc signing.")


def validate_policy(policy):
    require(isinstance(policy, dict) and policy.get("schemaVersion") == 1, "Unsupported signing policy.")
    require(bool(re.fullmatch(r"[0-9A-F]{40}", str(policy.get("identitySHA1", "")))), "Invalid pinned certificate.")
    require(bool(re.fullmatch(r"[A-Z0-9]{10}", str(policy.get("team", "")))), "Invalid pinned team.")
    require(str(policy.get("authority", "")).startswith(("Apple Development:", "Developer ID Application:")),
            "The policy must select an Apple-issued Mac identity.")
    require(isinstance(policy.get("requirements"), dict), "Missing signing requirements.")
    for configuration, bundle_id in IDS.items():
        requirement = policy.get("requirements", {}).get(configuration, "")
        require(isinstance(requirement, str) and requirement.startswith(f'identifier "{bundle_id}" and ')
                and "anchor apple generic" in requirement and "cdhash" not in requirement,
                "Missing stable designated requirement; run configure with an existing Apple identity.")
    return policy


def load_policy(*, check_key=True):
    path = config_path()
    require(path.is_file() and not path.is_symlink(),
            "Stable Mac signing is not configured. Run python3 tools/mac_signing.py configure --identity CERTIFICATE_SHA1. No ad-hoc fallback is permitted.")
    try:
        policy = validate_policy(json.loads(path.read_text()))
    except (ValueError, OSError, TypeError, AttributeError) as error:
        raise SigningError(f"Cannot read signing policy: {error}") from error
    if check_key:
        identities = run(["security", "find-identity", "-v", "-p", "codesigning"]).stdout.decode()
        require(select_identity(identities, policy["identitySHA1"]) == policy["authority"],
                "Pinned certificate name changed; inspect the signing policy.")
    return policy


def code_details(path, arch=None):
    args = ["codesign", "-d", "-r-", "--verbose=2"]
    if arch:
        args += ["--arch", arch]
    result = run([*args, path])
    text = (result.stdout + result.stderr).decode()
    fields = dict(re.findall(r"^([A-Za-z]+)=(.*)$", text, re.M))
    match = re.search(r"^(?:# )?designated => (.+)$", text, re.M)
    authority = re.search(r"^Authority=(.+)$", text, re.M)
    return {"requirement": match.group(1) if match else "", "team": fields.get("TeamIdentifier"),
            "authority": authority.group(1) if authority else None, "adHoc": fields.get("Signature") == "adhoc",
            "runtime": bool(re.search(r"^CodeDirectory\s+v=.*flags=.*\bruntime\b", text, re.M))}


def validate_rotation(previous, candidate):
    require(previous["team"] == candidate["team"] and previous["requirements"] == candidate["requirements"],
            "This identity changes the pinned application requirements. Stop: it requires an explicit migration and permission testing.")


def configure(digest):
    path = config_path()
    previous = load_policy(check_key=False) if path.exists() else None
    identities = run(["security", "find-identity", "-v", "-p", "codesigning"]).stdout.decode()
    authority = select_identity(identities, digest)
    with tempfile.TemporaryDirectory(prefix="displayweave-signing-probe-") as folder:
        probe = Path(folder) / "probe"
        run(["xcrun", "clang", "-x", "c", "-o", probe, "-"], input=b"int main(void) { return 0; }\n")
        run(["codesign", "--force", "--sign", digest, "--identifier", PROBE_ID,
             "--options", "runtime", "--timestamp", probe])
        run(["codesign", "--verify", "--strict", "-R=anchor apple generic", probe])
        details = code_details(probe)
    requirement = details["requirement"]
    require(requirement.startswith(f'identifier "{PROBE_ID}" and '), "Unexpected probe requirement.")
    policy = validate_policy({"schemaVersion": 1, "identitySHA1": digest.upper(),
        "authority": authority, "team": details["team"],
        "requirements": {configuration: requirement.replace(f'identifier "{PROBE_ID}"',
                         f'identifier "{bundle_id}"', 1) for configuration, bundle_id in IDS.items()}})
    if previous:
        validate_rotation(previous, policy)
    path.parent.mkdir(parents=True, exist_ok=True)
    # Only public identity metadata is saved. Private keys remain in Keychain.
    fd, temporary = tempfile.mkstemp(prefix=".mac-signing-", dir=path.parent)
    try:
        with os.fdopen(fd, "w") as stream:
            stream.write(json.dumps(policy, indent=2) + "\n")
        os.replace(temporary, path)
    finally:
        Path(temporary).unlink(missing_ok=True)
    return {"configured": str(path), "authority": authority, "team": policy["team"]}


def xcode_settings(policy, configuration):
    return ["CODE_SIGN_STYLE=Manual", f"CODE_SIGN_IDENTITY={policy['identitySHA1']}",
            f"DEVELOPMENT_TEAM={policy['team']}", "CODE_SIGNING_ALLOWED=YES", "CODE_SIGNING_REQUIRED=YES",
            "ENABLE_HARDENED_RUNTIME=YES", "CODE_SIGN_ENTITLEMENTS=Mac/OpenSidecarMac.entitlements",
            "CODE_SIGN_INJECT_BASE_ENTITLEMENTS=" + ("NO" if configuration == "Release" else "YES"),
            "OTHER_CODE_SIGN_FLAGS=--timestamp"]


def inspect_app(app):
    app = Path(app)
    require(app.is_dir(), f"Missing app: {app}")
    try:
        info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
        executable = info["CFBundleExecutable"]
    except (OSError, ValueError, KeyError) as error:
        raise SigningError(f"Cannot inspect app: {error}") from error
    require(isinstance(executable, str) and Path(executable).name == executable, "Invalid executable name.")
    run(["codesign", "--verify", "--deep", "--strict", "--all-architectures", app])
    arches = run(["xcrun", "lipo", "-archs", app / "Contents/MacOS" / executable]).stdout.decode().split()
    require(bool(arches), "App has no executable architectures.")
    details = {arch: code_details(app, arch) for arch in arches}
    raw = run(["codesign", "-d", "--entitlements", ":-", app]).stdout
    entitlements = plistlib.loads(raw) if raw.strip() else {}
    return {"info": info, "architectures": details, "entitlements": entitlements}


def validate_app(result, policy, configuration):
    info = result["info"]
    require(info.get("CFBundleIdentifier") == IDS[configuration], "App bundle ID changed.")
    require(info.get("SUFeedURL") == FEED and info.get("SUPublicEDKey") == UPDATE_KEY,
            "Update feed or Sparkle identity changed.")
    require(isinstance(result["entitlements"], dict), "Invalid entitlements.")
    for details in result["architectures"].values():
        require(not details["adHoc"], "Ad-hoc app rejected: permissions cannot reliably survive updates.")
        require(details["runtime"] and details["team"] == policy["team"], "Wrong signing team or missing hardened runtime.")
        require(details["requirement"] == policy["requirements"][configuration],
                "Designated requirement changed; this would break application identity continuity.")
    if configuration == "Release":
        require(set(result["architectures"]) == {"arm64", "x86_64"}, "Release must retain both Mac architectures.")
        require(not result["entitlements"], "Signed release must use its empty entitlement set.")


def verify(app, policy, configuration):
    result = inspect_app(app)
    validate_app(result, policy, configuration)
    run(["codesign", "--verify", "--strict", "--all-architectures",
         "-R=" + policy["requirements"][configuration], app])
    with tempfile.TemporaryDirectory(prefix="displayweave-signature-check-") as folder:
        for arch in result["architectures"]:
            prefix = Path(folder) / arch
            run(["codesign", "-d", "--arch", arch, f"--extract-certificates={prefix}", app])
            digest = hashlib.sha1(Path(str(prefix) + "0").read_bytes()).hexdigest().upper()
            require(digest == policy["identitySHA1"], "Artifact was signed by a different leaf certificate.")
    return result


def compare_results(baseline, candidate, allow_adhoc_migration=False):
    require(baseline["info"].get("CFBundleIdentifier") == candidate["info"].get("CFBundleIdentifier"),
            "Upgrade changes the bundle ID.")
    old = baseline["architectures"]
    new = candidate["architectures"]
    require(set(old) == set(new), "Upgrade changes supported CPU architectures.")
    migration = all(value["adHoc"] for value in old.values())
    if migration:
        require(allow_adhoc_migration, "The installed app is ad-hoc signed; initial migration needs explicit --allow-adhoc-migration and may need reauthorization.")
        require(not any(value["adHoc"] for value in new.values()), "Migration candidate must have a stable signature.")
    else:
        require(all(old[arch]["requirement"] == new[arch]["requirement"] and
                    old[arch]["team"] == new[arch]["team"] and not new[arch]["adHoc"] for arch in old),
                "Upgrade breaks the installed application's signing identity.")
    return {"identityContinues": not migration, "initialMigrationNeedsReauthorization": migration}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)
    configure_parser = sub.add_parser("configure")
    configure_parser.add_argument("--identity", required=True)
    for command in ("xcode-settings", "verify", "compare"):
        p = sub.add_parser(command)
        p.add_argument("--configuration", choices=IDS, default="Release")
        if command != "xcode-settings":
            p.add_argument("app", type=Path)
        if command == "compare":
            p.add_argument("--baseline", required=True, type=Path)
            p.add_argument("--allow-adhoc-migration", action="store_true")
    options = parser.parse_args()
    if options.command == "configure":
        print(json.dumps(configure(options.identity), indent=2))
        return
    policy = load_policy(check_key=options.command == "xcode-settings")
    if options.command == "xcode-settings":
        print("\n".join(xcode_settings(policy, options.configuration)))
        return
    result = verify(options.app, policy, options.configuration)
    report = {"verified": str(options.app), "version": result["info"].get("CFBundleShortVersionString"),
              "build": result["info"].get("CFBundleVersion"), "team": policy["team"],
              "architectures": list(result["architectures"]),
              "requirement": policy["requirements"][options.configuration]}
    if options.command == "compare":
        require(options.app.resolve() != options.baseline.resolve(), "Use a separate previous build as the upgrade baseline.")
        baseline = inspect_app(options.baseline)
        report.update(compare_results(baseline, result, options.allow_adhoc_migration))
    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    try:
        main()
    except (SigningError, OSError, ValueError) as error:
        print(f"Mac signing: {error}", file=sys.stderr)
        sys.exit(1)

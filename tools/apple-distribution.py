#!/usr/bin/env python3
"""Local production Apple archives. No publication, key creation, or app installation."""
import argparse
import datetime as dt
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import shutil
import signal
import subprocess
import sys
import uuid

MAC_ID = "app.displayweave.mac"
IOS_ID = "com.cyh.opendisplay.receiver"
FEED = "https://chenyuhao0628.github.io/displayweave/appcast.xml"
SPARKLE_KEY = "N9dMZV/F1ui58IsEmCv5jFVgDWiWv2yB/01KBlAHFjE="
ROOT = Path(__file__).resolve().parent.parent


class DistributionError(Exception):
    pass


def require(value, message):
    if not value:
        raise DistributionError(message)


def select_identity(output, sha1, team, platform):
    require(bool(re.fullmatch(r"[A-Fa-f0-9]{40}", sha1 or "")), "Provide the distribution certificate SHA-1 (40 hex digits).")
    require(bool(re.fullmatch(r"[A-Z0-9]{10}", team or "")), "Provide the 10-character Apple team ID.")
    prefix = "Developer ID Application:" if platform == "mac" else "Apple Distribution:"
    for digest, name in re.findall(r'([A-Fa-f0-9]{40})\s+"([^"]+)"', output):
        if digest.upper() == sha1.upper() and name.startswith(prefix) and name.endswith(f"({team})"):
            return digest.upper()
    raise DistributionError(f"No usable {prefix} certificate with the selected SHA-1 and team. Install its certificate and private key in Keychain.")


def validate_profile(profile, team, sha1, method):
    require(method in ("release-testing", "app-store-connect"), "Select release-testing or app-store-connect.")
    require(profile.get("TeamIdentifier") == [team], "Provisioning profile team does not match.")
    expires = profile.get("ExpirationDate")
    require(isinstance(expires, dt.datetime), "Profile has no valid expiration date.")
    require(expires.replace(tzinfo=dt.timezone.utc) > dt.datetime.now(dt.timezone.utc), "Provisioning profile has expired; install a renewed profile.")
    certs = profile.get("DeveloperCertificates", [])
    require(any(isinstance(cert, bytes) and hashlib.sha1(cert).hexdigest().upper() == sha1.upper() for cert in certs), "Selected distribution certificate is absent from the profile.")
    prefixes = profile.get("ApplicationIdentifierPrefix", [])
    entitlements = profile.get("Entitlements", {})
    require(isinstance(prefixes, list) and len(prefixes) == 1 and isinstance(prefixes[0], str), "Profile application prefix is missing or ambiguous.")
    require(entitlements.get("application-identifier") == f"{prefixes[0]}.{IOS_ID}", "Profile must name the exact receiver bundle ID (no wildcard).")
    require(entitlements.get("get-task-allow") is False, "A distribution profile must disable debugging.")
    require(not profile.get("ProvisionsAllDevices"), "Enterprise distribution is not supported by this workflow.")
    devices = profile.get("ProvisionedDevices")
    require(isinstance(devices, list) and bool(devices) if method == "release-testing" else devices is None,
            "Profile device list does not match the selected export method.")
    try:
        uuid.UUID(profile["UUID"])
    except (KeyError, ValueError, TypeError, AttributeError):
        raise DistributionError("Profile UUID is missing or invalid.")
    return profile["UUID"]


def export_options(platform, team, sha1, method, profile_uuid):
    result = {"method": "developer-id" if platform == "mac" else method,
              "destination": "export", "teamID": team, "signingStyle": "manual",
              "signingCertificate": sha1, "manageAppVersionAndBuildNumber": False}
    if platform == "ios":
        result.update({"provisioningProfiles": {IOS_ID: profile_uuid}, "thinning": "<none>"})
    return result


def validate_info(info, platform, version, build):
    for key, expected in {"CFBundleIdentifier": MAC_ID if platform == "mac" else IOS_ID,
                          "CFBundleShortVersionString": version, "CFBundleVersion": build}.items():
        require(info.get(key) == expected, f"Exported {key} does not match the requested release.")
    if platform == "mac":
        require(info.get("SUFeedURL") == FEED, "Exported feed must use GitHub Pages.")
        require(info.get("SUPublicEDKey") == SPARKLE_KEY, "Exported Sparkle public key changed; stop and investigate.")


def validate_entitlements(entitlements, platform):
    require(isinstance(entitlements, dict), "Unable to inspect actual code entitlements.")
    forbidden = ("get-task-allow", "com.apple.security.get-task-allow", "com.apple.security.cs.disable-library-validation",
                 "com.apple.security.cs.allow-unsigned-executable-memory", "com.apple.security.cs.allow-dyld-environment-variables")
    require(not any(entitlements.get(key) for key in forbidden), "Export contains debug or weakened runtime entitlements.")
    if platform == "mac":
        require(not entitlements, "Production Mac app must use its empty entitlement set.")


def accept_notary(result):
    require(isinstance(result, dict) and result.get("status") == "Accepted", "Notarization is not Accepted. Preserve this directory and inspect its submission ID/log before retrying.")
    require(bool(result.get("id")), "Notary response lacks a submission ID.")


def reserve_output(output, root):
    output, root = Path(output).absolute(), Path(root).resolve()
    # Release output is deliberately restricted to ignored local build storage.
    require(output.parent.resolve().is_relative_to(root / "build"), "Use a new directory below this repository's build/ directory.")
    require(not output.exists() and not output.is_symlink(), "Output already exists; use a new directory. Existing evidence is never overwritten.")
    output.parent.mkdir(parents=True, exist_ok=True)
    output.mkdir(mode=0o700, exist_ok=False)
    (output / "INCOMPLETE").write_text("Unverified production candidate. Do not distribute.\n")
    return output


def archive_arguments(platform, root, work, team, identity, version, build, profile_uuid):
    args = ["xcodebuild", "-quiet", "-project", str(root / "OpenSidecar.xcodeproj"),
            "-scheme", "OpenSidecarMac" if platform == "mac" else "OpenSidecariOS",
            "-configuration", "Release", "-destination", "generic/platform=macOS" if platform == "mac" else "generic/platform=iOS",
            "-archivePath", str(work / "DisplayWeave.xcarchive"), "-derivedDataPath", str(work / "DerivedData"),
            "-clonedSourcePackagesDirPath", str(work / "SourcePackages"), "CODE_SIGN_STYLE=Manual",
            f"DEVELOPMENT_TEAM={team}", f"CODE_SIGN_IDENTITY={identity}", f"MARKETING_VERSION={version}",
            f"CURRENT_PROJECT_VERSION={build}", "CODE_SIGNING_ALLOWED=YES", "CODE_SIGNING_REQUIRED=YES",
            "ONLY_ACTIVE_ARCH=NO"]
    if platform == "mac":
        args += ["ARCHS=arm64 x86_64", "ENABLE_HARDENED_RUNTIME=YES", "OTHER_CODE_SIGN_FLAGS=--timestamp",
                 "CODE_SIGN_ENTITLEMENTS=Mac/OpenSidecarMac.entitlements", "CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO"]
    else:
        args += ["ARCHS=arm64", f"PROVISIONING_PROFILE_SPECIFIER={profile_uuid}"]
    return args + ["archive"]


class Runner:
    def __init__(self, root, logs=None):
        self.root, self.logs, self.index = root, logs, 0

    def run(self, args, timeout=120, merge=False):
        self.index += 1
        process = subprocess.Popen([str(a) for a in args], cwd=self.root, stdout=subprocess.PIPE,
                                   stderr=subprocess.PIPE, start_new_session=True)
        try:
            stdout, stderr = process.communicate(timeout=timeout)
        except subprocess.TimeoutExpired:
            os.killpg(process.pid, signal.SIGTERM)
            try:
                stdout, stderr = process.communicate(timeout=5)
            except subprocess.TimeoutExpired:
                os.killpg(process.pid, signal.SIGKILL)
                stdout, stderr = process.communicate(timeout=5)
            if self.logs:
                (self.logs / f"{self.index:02d}-timeout.log").write_bytes(stdout + stderr)
            raise DistributionError(f"{Path(args[0]).name} timed out; retained logs may include an in-progress notary submission. Do not assume acceptance.")
        result = subprocess.CompletedProcess(args, process.returncode, stdout, stderr)
        if self.logs:
            (self.logs / f"{self.index:02d}-{Path(args[0]).name}.log").write_bytes(result.stdout + result.stderr)
        require(result.returncode == 0, f"{Path(args[0]).name} failed (exit {result.returncode}); inspect the retained logs or rerun preflight after repairing prerequisites.")
        return result.stdout + result.stderr if merge else result.stdout


def profile_from_path(path, runner):
    require(path is not None and path.is_file(), "Provide an installed iOS distribution provisioning profile with --profile.")
    return plistlib.loads(runner.run(["security", "cms", "-D", "-i", path]))


def preflight(options, runner):
    for command in ("xcodebuild", "xcodegen", "security", "codesign", "xcrun", "ditto", "git"):
        require(shutil.which(command), f"Missing {command}; install/select the Apple build tools first.")
    identities = runner.run(["security", "find-identity", "-v", "-p", "codesigning"]).decode()
    identity = select_identity(identities, options.identity, options.team, options.platform)
    profile_uuid = None
    if options.platform == "mac":
        require(options.notary_profile, "Provide an existing notarytool Keychain profile with --notary-profile.")
        require(options.sparkle_bin and (options.sparkle_bin / "generate_keys").is_file() and (options.sparkle_bin / "sign_update").is_file(), "Provide the resolved Sparkle bin directory with --sparkle-bin.")
        public = runner.run([options.sparkle_bin / "generate_keys", "--account", "ed25519", "-p"]).decode().strip()
        require(public == SPARKLE_KEY, "Existing Sparkle Keychain public key does not match; restore the original key, never generate a replacement.")
        # Read-only authentication check. No submission or credential storage.
        runner.run(["xcrun", "notarytool", "history", "--keychain-profile", options.notary_profile, "--output-format", "json"], timeout=120)
    else:
        profile = profile_from_path(options.profile, runner)
        profile_uuid = validate_profile(profile, options.team, identity, options.method)
        installed_roots = [Path.home() / "Library/MobileDevice/Provisioning Profiles",
                           Path.home() / "Library/Developer/Xcode/UserData/Provisioning Profiles"]
        require(any(options.profile.resolve().is_relative_to(folder.resolve()) for folder in installed_roots),
                "Install this matching provisioning profile through Xcode before archiving; preflight does not install profiles.")
    return identity, profile_uuid


def verify_app(app, options, runner, work):
    contents = app / "Contents" if options.platform == "mac" else app
    info = plistlib.loads((contents / "Info.plist").read_bytes())
    validate_info(info, options.platform, options.version, options.build_number)
    executable = info.get("CFBundleExecutable", "")
    require(executable and Path(executable).name == executable, "Invalid bundle executable path.")
    executable = contents / "MacOS" / executable if options.platform == "mac" else contents / executable
    arches = set(runner.run(["lipo", "-archs", executable]).decode().split())
    require(arches == ({"arm64", "x86_64"} if options.platform == "mac" else {"arm64"}), "Exported architectures are incomplete or unexpected.")
    runner.run(["codesign", "--verify", "--deep", "--strict", "--verbose=2", app])
    details = runner.run(["codesign", "-d", "--verbose=4", app], merge=True).decode()
    require(f"TeamIdentifier={options.team}\n" in details, "Actual signature team mismatch.")
    if options.platform == "mac":
        require("runtime" in details and "Timestamp=" in details, "Actual signature lacks hardened runtime or a trusted timestamp.")
    certificate_prefix = work / ("mac-certificate-" if options.platform == "mac" else "ios-certificate-")
    runner.run(["codesign", "-d", "--extract-certificates", certificate_prefix, app])
    require(hashlib.sha1(Path(str(certificate_prefix) + "0").read_bytes()).hexdigest().upper() == options.identity.upper(), "Actual signing leaf does not match the requested certificate.")
    entitlements = runner.run(["codesign", "-d", "--entitlements", ":-", app])
    require(bool(entitlements.strip()) or options.platform == "mac", "iOS export lacks entitlements.")
    parsed = plistlib.loads(entitlements) if entitlements.strip() else {}
    validate_entitlements(parsed, options.platform)
    if options.platform == "ios":
        embedded = profile_from_path(app / "embedded.mobileprovision", runner)
        validate_profile(embedded, options.team, options.identity, options.method)
        require(embedded["UUID"] == options.profile_uuid, "Export substituted a different profile.")
        require(parsed.get("application-identifier") == embedded["Entitlements"]["application-identifier"] and
                parsed.get("com.apple.developer.team-identifier") == options.team, "Exported application/team entitlement mismatch.")
    return info


def one(paths, description):
    paths = list(paths)
    require(len(paths) == 1, f"Expected exactly one {description}; got {len(paths)}.")
    return paths[0]


def build_distribution(options, runner, output):
    work, logs = output / "work", output / "logs"
    work.mkdir(); logs.mkdir(); runner.logs = logs
    source = runner.run(["git", "rev-parse", "HEAD"]).decode().strip()
    runner.run(["xcodegen", "generate"])
    runner.run(archive_arguments(options.platform, ROOT, work, options.team, options.identity,
                                options.version, options.build_number, options.profile_uuid), timeout=3600)
    export_plist = work / "ExportOptions.plist"
    export_plist.write_bytes(plistlib.dumps(export_options(options.platform, options.team, options.identity, options.method, options.profile_uuid)))
    export = work / "export"
    runner.run(["xcodebuild", "-quiet", "-exportArchive", "-archivePath", work / "DisplayWeave.xcarchive",
                "-exportOptionsPlist", export_plist, "-exportPath", export], timeout=1800)
    notary = None
    if options.platform == "mac":
        app = one(export.glob("*.app"), "exported Mac app")
        verify_app(app, options, runner, work)
        submission = work / "notary-input.zip"
        runner.run(["ditto", "-c", "-k", "--sequesterRsrc", "--keepParent", app, submission], timeout=300)
        notary = json.loads(runner.run(["xcrun", "notarytool", "submit", submission,
            "--keychain-profile", options.notary_profile, "--output-format", "json", "--wait", "--timeout", "30m"], timeout=1860))
        (output / "notary.json").write_text(json.dumps(notary, indent=2) + "\n")
        accept_notary(notary)
        runner.run(["xcrun", "stapler", "staple", app], timeout=300)
        runner.run(["xcrun", "stapler", "validate", app], timeout=300)
        runner.run(["spctl", "--assess", "--type", "execute", "--verbose=2", app], timeout=300)
        runner.run(["codesign", "--verify", "--deep", "--strict", app])
        artifact = output / "DisplayWeave-macOS.zip"
        runner.run(["ditto", "-c", "-k", "--sequesterRsrc", "--keepParent", app, artifact], timeout=300)
        sign = options.sparkle_bin / "sign_update"
        signature = runner.run([sign, "--account", "ed25519", "-p", artifact]).decode().strip()
        require(bool(re.fullmatch(r"[A-Za-z0-9+/]{86}==", signature)), "Sparkle did not return an Ed25519 signature.")
        runner.run([sign, "--account", "ed25519", "--verify", artifact, signature])
        (output / "sparkle-signature.txt").write_text(signature + "\n")
    else:
        ipa = one(export.glob("*.ipa"), "exported IPA")
        extracted = work / "ipa"
        runner.run(["ditto", "-x", "-k", ipa, extracted], timeout=300)
        app = one((extracted / "Payload").glob("*.app"), "IPA app")
        verify_app(app, options, runner, work)
        artifact = output / "DisplayWeave-iOS.ipa"
        shutil.copyfile(ipa, artifact)
    require(not runner.run(["git", "status", "--porcelain"]).strip(), "Tracked/unignored source changed during build. Preserve candidate and rebuild from a clean commit.")
    digest = sha256(artifact)
    receipt = {"schemaVersion": 1, "commit": source, "platform": options.platform,
               "version": options.version, "build": options.build_number, "artifact": artifact.name,
               "sha256": digest, "bytes": artifact.stat().st_size, "team": options.team,
               "signingCertificateSHA1": options.identity, "profileUUID": options.profile_uuid,
               "notarySubmission": notary.get("id") if notary else None,
               "xcode": runner.run(["xcodebuild", "-version"]).decode().strip(),
               "builtAt": dt.datetime.now(dt.timezone.utc).isoformat(), "publication": "not uploaded"}
    (output / "SHA256SUMS.txt").write_text(f"{digest}  {artifact.name}\n")
    (output / "receipt.json").write_text(json.dumps(receipt, indent=2) + "\n")
    (output / "INCOMPLETE").unlink()
    return artifact


def sha256(path):
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=("preflight", "build"))
    parser.add_argument("platform", choices=("mac", "ios"))
    parser.add_argument("--team")
    parser.add_argument("--identity", help="exact distribution certificate SHA-1, never a password")
    parser.add_argument("--notary-profile", help="existing notarytool Keychain profile name")
    parser.add_argument("--sparkle-bin", type=Path)
    parser.add_argument("--profile", type=Path, help="installed iOS provisioning profile")
    parser.add_argument("--method", choices=("release-testing", "app-store-connect"), default="release-testing")
    parser.add_argument("--version")
    parser.add_argument("--build-number")
    parser.add_argument("--output", type=Path)
    options = parser.parse_args()
    runner = Runner(ROOT)
    try:
        options.identity, options.profile_uuid = preflight(options, runner)
        if options.command == "preflight":
            print("PASS: distribution prerequisites validated. No artifact was built or published.")
            return 0
        require(bool(re.fullmatch(r"\d+\.\d+\.\d+", options.version or "")), "Production version must be numeric x.y.z.")
        require(bool(re.fullmatch(r"[1-9][0-9]{0,8}", options.build_number or "")), "Provide a positive build number up to nine digits, above every public build.")
        require(options.output is not None, "Provide a new --output below build/.")
        require(not runner.run(["git", "status", "--porcelain"]).strip(), "Commit or preserve source changes before building production artifacts.")
        output = reserve_output(options.output, ROOT)
        artifact = build_distribution(options, runner, output)
        print(f"PASS: verified local {artifact.name}. See {output / 'receipt.json'}. Publication remains a separate GitHub-only action.")
        return 0
    except (DistributionError, OSError, ValueError, plistlib.InvalidFileException) as error:
        print(f"BLOCKED: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())

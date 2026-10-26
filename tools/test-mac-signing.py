#!/usr/bin/env python3
"""Offline policy/entry-point regressions; does not access a real Keychain."""
import copy
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest
from unittest.mock import patch

import mac_signing as signing

FINGERPRINT = "A" * 40
TEAM = "ABCDEFGHIJ"
AUTHORITY = "Apple Development: Test Developer (1234567890)"


def policy():
    return {"schemaVersion": 1, "identitySHA1": FINGERPRINT, "team": TEAM, "authority": AUTHORITY,
            "requirements": {configuration: f'identifier "{bundle}" and anchor apple generic and certificate leaf[subject.CN] = "{AUTHORITY}"'
                             for configuration, bundle in signing.IDS.items()}}


def app(configuration="Release", ad_hoc=False):
    details = {"requirement": policy()["requirements"][configuration], "team": TEAM,
               "adHoc": ad_hoc, "runtime": True}
    return {"info": {"CFBundleIdentifier": signing.IDS[configuration], "SUFeedURL": signing.FEED,
                     "SUPublicEDKey": signing.UPDATE_KEY, "CFBundleVersion": "18"},
            "architectures": {"arm64": copy.deepcopy(details), "x86_64": copy.deepcopy(details)},
            "entitlements": {}}


class SigningTests(unittest.TestCase):
    def test_codesign_output_reports_runtime_and_team(self):
        output = b'CodeDirectory v=20500 size=256 flags=0x10000(runtime) hashes=2+2 location=embedded\nTeamIdentifier=ABCDEFGHIJ\n'
        result = subprocess.CompletedProcess([], 0, b'designated => identifier "fixture" and anchor apple generic\n', output)
        with patch.object(signing, "run", return_value=result):
            details = signing.code_details("fixture")
        self.assertTrue(details["runtime"])
        self.assertEqual(details["team"], TEAM)

    def test_exact_existing_apple_identity(self):
        listing = f'1) {FINGERPRINT} "{AUTHORITY}"\n'
        self.assertEqual(signing.select_identity(listing, FINGERPRINT.lower()), AUTHORITY)

    def test_no_ad_hoc_or_missing_identity_fallback(self):
        for fingerprint in ("-", "", FINGERPRINT):
            with self.subTest(fingerprint=fingerprint), self.assertRaises(signing.SigningError):
                signing.select_identity("0 valid identities found", fingerprint)

    def test_self_signed_identity_rejected(self):
        with self.assertRaises(signing.SigningError):
            signing.select_identity(f'1) {FINGERPRINT} "MacToolbox Local Signing"', FINGERPRINT)

    def test_expired_identity_is_not_selected(self):
        with self.assertRaises(signing.SigningError):
            signing.select_identity(f'1) {FINGERPRINT} "{AUTHORITY}" (CSSMERR_TP_CERT_EXPIRED)', FINGERPRINT)

    def test_policy_requires_both_stable_bundle_requirements(self):
        for configuration in signing.IDS:
            p = policy()
            p["requirements"][configuration] = 'cdhash H"0000"'
            with self.assertRaises(signing.SigningError):
                signing.validate_policy(p)

    def test_renewal_only_when_team_and_requirements_continue(self):
        renewed = policy()
        renewed["identitySHA1"] = "B" * 40
        signing.validate_rotation(policy(), renewed)
        for field, value in (("team", "OTHERTEAM1"), ("requirements", {"Release": "different"})):
            changed = policy()
            changed[field] = value
            with self.assertRaises(signing.SigningError):
                signing.validate_rotation(policy(), changed)

    def test_release_settings_do_not_relax_library_validation(self):
        args = signing.xcode_settings(policy(), "Release")
        self.assertIn("CODE_SIGN_IDENTITY=" + FINGERPRINT, args)
        self.assertIn("DEVELOPMENT_TEAM=" + TEAM, args)
        self.assertIn("CODE_SIGN_ENTITLEMENTS=Mac/OpenSidecarMac.entitlements", args)
        self.assertIn("CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO", args)

    def test_all_architectures_verified(self):
        signing.validate_app(app(), policy(), "Release")
        for field, value in (("adHoc", True), ("team", "OTHERTEAM1"),
                             ("requirement", "other"), ("runtime", False)):
            candidate = app()
            candidate["architectures"]["x86_64"][field] = value
            with self.subTest(field=field), self.assertRaises(signing.SigningError):
                signing.validate_app(candidate, policy(), "Release")

    def test_debug_cannot_replace_release(self):
        with self.assertRaises(signing.SigningError):
            signing.validate_app(app("Debug"), policy(), "Release")

    def test_update_feed_key_and_identity_preserved(self):
        for key in ("CFBundleIdentifier", "SUFeedURL", "SUPublicEDKey"):
            candidate = app()
            candidate["info"][key] = "different"
            with self.subTest(key=key), self.assertRaises(signing.SigningError):
                signing.validate_app(candidate, policy(), "Release")

    def test_release_rejects_debug_and_relaxed_entitlements(self):
        for entitlement in ("com.apple.security.get-task-allow", "com.apple.security.cs.disable-library-validation"):
            candidate = app()
            candidate["entitlements"][entitlement] = True
            with self.assertRaises(signing.SigningError):
                signing.validate_app(candidate, policy(), "Release")

    def test_two_distinct_builds_keep_identity(self):
        newer = app()
        newer["info"]["CFBundleVersion"] = "19"
        self.assertEqual(signing.compare_results(app(), newer),
                         {"identityContinues": True, "initialMigrationNeedsReauthorization": False})

    def test_initial_adhoc_migration_is_explicit(self):
        old = app(ad_hoc=True)
        with self.assertRaises(signing.SigningError):
            signing.compare_results(old, app())
        self.assertTrue(signing.compare_results(old, app(), True)["initialMigrationNeedsReauthorization"])
        with self.assertRaises(signing.SigningError):
            signing.compare_results(old, app(ad_hoc=True), True)

    def test_never_return_to_adhoc_even_with_migration_flag(self):
        with self.assertRaises(signing.SigningError):
            signing.compare_results(app(), app(ad_hoc=True), True)

    def test_upgrade_rejects_identity_or_architecture_change(self):
        for alteration in ("requirement", "team", "architecture", "bundle"):
            candidate = app()
            if alteration == "architecture":
                del candidate["architectures"]["x86_64"]
            elif alteration == "bundle":
                candidate["info"]["CFBundleIdentifier"] += ".debug"
            else:
                candidate["architectures"]["arm64"][alteration] = "changed"
            with self.subTest(alteration=alteration), self.assertRaises(signing.SigningError):
                signing.compare_results(app(), candidate, True)

    def test_missing_config_does_not_query_or_create_keys(self):
        with tempfile.TemporaryDirectory() as d, patch.dict(os.environ, DISPLAYWEAVE_MAC_SIGNING_CONFIG=str(Path(d) / "missing.json")):
            with patch.object(signing, "run") as run:
                with self.assertRaises(signing.SigningError):
                    signing.load_policy()
                run.assert_not_called()

    def test_entry_points_stop_before_build_when_identity_missing(self):
        # Execute the actual shell entry points in an isolated fake checkout.
        # Before the fix, build_and_run called Xcode with CODE_SIGN_IDENTITY=-.
        for script in ("script/build_and_run.sh", "tools/package-release.sh"):
            with self.subTest(script=script), tempfile.TemporaryDirectory() as d:
                d = Path(d)
                (d / "tools").mkdir()
                (d / "script").mkdir()
                (d / "bin").mkdir()
                shutil.copyfile(signing.ROOT / script, d / script)
                shutil.copyfile(signing.ROOT / "tools/mac_signing.py", d / "tools/mac_signing.py")
                for command in ("xcodegen", "xcodebuild"):
                    stub = d / "bin" / command
                    stub.write_text('#!/bin/sh\necho called >> "$TEST_SIGNING_COMMAND_LOG"\n')
                    stub.chmod(0o755)
                env = dict(os.environ, DISPLAYWEAVE_VERSION_NAME="0.3.2", DISPLAYWEAVE_BUILD_NUMBER="21", PATH=str(d / "bin") + os.pathsep + os.environ["PATH"],
                           DISPLAYWEAVE_MAC_SIGNING_CONFIG=str(d / "missing.json"),
                           TEST_SIGNING_COMMAND_LOG=str(d / "commands.log"))
                result = subprocess.run(["bash", str(d / script), "--verify"], cwd=d, env=env,
                                        capture_output=True, text=True, timeout=30)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("No ad-hoc fallback", result.stderr)
                self.assertFalse((d / "commands.log").exists())

    def test_update_packaging_requires_previous_release(self):
        self.check_packaging_preflight(existing_output=False, expected="DISPLAYWEAVE_MAC_BASELINE_APP")

    def test_packaging_preserves_existing_output(self):
        self.check_packaging_preflight(existing_output=True, expected="output already exists")

    def check_packaging_preflight(self, existing_output, expected):
        with tempfile.TemporaryDirectory() as d:
            d = Path(d)
            (d / "tools").mkdir()
            (d / "bin").mkdir()
            for file in ("tools/mac_signing.py", "tools/package-release.sh"):
                shutil.copyfile(signing.ROOT / file, d / file)
            config = d / "policy.json"
            config.write_text(json.dumps(policy()))
            security = d / "bin/security"
            security.write_text(f'#!/bin/sh\nprintf \'%s\\n\' \'1) {FINGERPRINT} "{AUTHORITY}"\'\n')
            security.chmod(0o755)
            output = d / "output"
            if existing_output:
                output.mkdir()
                (output / "published.txt").write_text("preserve me")
            env = dict(os.environ, DISPLAYWEAVE_VERSION_NAME="0.3.2", DISPLAYWEAVE_BUILD_NUMBER="21", PATH=str(d / "bin") + os.pathsep + os.environ["PATH"],
                       DISPLAYWEAVE_MAC_SIGNING_CONFIG=str(config), DISPLAYWEAVE_UPDATE_RELEASE="1",
                       DISPLAYWEAVE_OUTPUT_DIR=str(output), DISPLAYWEAVE_MAC_BASELINE_APP=str(d / "missing.app"))
            result = subprocess.run(["bash", str(d / "tools/package-release.sh")], env=env, cwd=d,
                                    capture_output=True, text=True, timeout=30)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn(expected, result.stderr)
            if existing_output:
                self.assertEqual((output / "published.txt").read_text(), "preserve me")
            else:
                self.assertFalse(output.exists())


if __name__ == "__main__":
    unittest.main()

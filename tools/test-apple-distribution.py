#!/usr/bin/env python3
"""Offline distribution gate tests; no signing keys, Apple uploads or application launches."""
import datetime as dt
import hashlib
import importlib.util
import pathlib
import plistlib
import tempfile
import unittest
from unittest.mock import patch
from types import SimpleNamespace

spec = importlib.util.spec_from_file_location("apple_distribution", pathlib.Path(__file__).with_name("apple-distribution.py"))
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class DistributionTests(unittest.TestCase):
    def test_identity_requires_exact_team_and_distribution_type(self):
        sha = "A" * 40
        identities = f'  1) {sha} "Apple Development: Test (ABCDEFGHIJ)"\n'
        with self.assertRaises(module.DistributionError):
            module.select_identity(identities, sha, "ABCDEFGHIJ", "mac")
        identities = identities.replace("Apple Development", "Developer ID Application")
        self.assertEqual(module.select_identity(identities, sha, "ABCDEFGHIJ", "mac"), sha)
        with self.assertRaises(module.DistributionError):
            module.select_identity(identities, sha, "KLMNOPQRST", "mac")

    def profile(self):
        certificate = b"public synthetic certificate"
        return {
            "UUID": "11111111-2222-4333-8444-555555555555", "Name": "Synthetic",
            "TeamIdentifier": ["ABCDEFGHIJ"], "ApplicationIdentifierPrefix": ["ABCDEFGHIJ"],
            "ExpirationDate": dt.datetime.now(dt.timezone.utc).replace(tzinfo=None) + dt.timedelta(days=30),
            "DeveloperCertificates": [certificate], "ProvisionedDevices": ["synthetic-device"],
            "Entitlements": {"application-identifier": "ABCDEFGHIJ.com.cyh.opendisplay.receiver", "get-task-allow": False},
        }, hashlib.sha1(certificate).hexdigest().upper()

    def test_profile_identity_expiry_bundle_and_method(self):
        profile, sha = self.profile()
        module.validate_profile(profile, "ABCDEFGHIJ", sha, "release-testing")
        for field, value in [("ExpirationDate", dt.datetime(2020, 1, 1)), ("DeveloperCertificates", [b"wrong"]),
                             ("TeamIdentifier", ["KLMNOPQRST"]), ("ProvisionsAllDevices", True)]:
            invalid = dict(profile, **{field: value})
            with self.assertRaises(module.DistributionError):
                module.validate_profile(invalid, "ABCDEFGHIJ", sha, "release-testing")
        invalid = dict(profile, Entitlements={"application-identifier": "ABCDEFGHIJ.*", "get-task-allow": False})
        with self.assertRaises(module.DistributionError):
            module.validate_profile(invalid, "ABCDEFGHIJ", sha, "release-testing")
        with self.assertRaises(module.DistributionError):
            module.validate_profile(profile, "ABCDEFGHIJ", sha, "app-store-connect")
        del profile["ProvisionedDevices"]
        module.validate_profile(profile, "ABCDEFGHIJ", sha, "app-store-connect")

    def test_export_cannot_upload_or_change_version(self):
        value = module.export_options("ios", "ABCDEFGHIJ", "A" * 40, "release-testing", "synthetic-profile")
        self.assertEqual(value["destination"], "export")
        self.assertFalse(value["manageAppVersionAndBuildNumber"])
        self.assertEqual(value["provisioningProfiles"], {module.IOS_ID: "synthetic-profile"})
        self.assertEqual(module.export_options("mac", "ABCDEFGHIJ", "A" * 40, None, None)["method"], "developer-id")

    def test_bundle_rejects_identity_feed_key_and_debug_entitlements(self):
        info = {"CFBundleIdentifier": module.MAC_ID, "CFBundleShortVersionString": "0.3.0", "CFBundleVersion": "16",
                "SUFeedURL": module.FEED, "SUPublicEDKey": module.SPARKLE_KEY}
        module.validate_info(info, "mac", "0.3.0", "16")
        for key, value in [("CFBundleIdentifier", "other"), ("SUPublicEDKey", "new-key"), ("SUFeedURL", "http://unsafe")]:
            with self.assertRaises(module.DistributionError):
                module.validate_info(dict(info, **{key: value}), "mac", "0.3.0", "16")
        for key in ["get-task-allow", "com.apple.security.get-task-allow", "com.apple.security.cs.disable-library-validation"]:
            with self.assertRaises(module.DistributionError): module.validate_entitlements({key: True}, "mac")
        module.validate_entitlements({}, "mac")

    def test_notary_requires_accepted_and_existing_output_is_immutable(self):
        for status in ["Invalid", "In Progress", "Rejected", "", None]:
            with self.assertRaises(module.DistributionError): module.accept_notary({"status": status})
        module.accept_notary({"status": "Accepted", "id": "11111111-2222-4333-8444-555555555555"})
        with tempfile.TemporaryDirectory() as folder:
            root = pathlib.Path(folder)
            output = root / "build" / "distribution"
            module.reserve_output(output, root)
            marker = output / "preserve"; marker.write_text("existing")
            with self.assertRaises(module.DistributionError): module.reserve_output(output, root)
            self.assertEqual(marker.read_text(), "existing")
            with self.assertRaises(module.DistributionError): module.reserve_output(root, root)

    def test_build_arguments_keep_manual_signing_and_production_entitlements(self):
        args = module.archive_arguments("mac", pathlib.Path("/repo"), pathlib.Path("/output/work"),
            "ABCDEFGHIJ", "A" * 40, "0.3.0", "16", None)
        self.assertIn("CODE_SIGN_STYLE=Manual", args)
        self.assertIn("ARCHS=arm64 x86_64", args)
        self.assertIn("CODE_SIGN_ENTITLEMENTS=Mac/OpenSidecarMac.entitlements", args)
        self.assertNotIn("-allowProvisioningUpdates", args)
        self.assertFalse(any("AdHoc" in value for value in args))

    def test_legacy_application_prefix_is_valid_but_debug_profile_is_not(self):
        profile, sha = self.profile()
        profile["ApplicationIdentifierPrefix"] = ["LEGACYPREF"]
        profile["Entitlements"]["application-identifier"] = "LEGACYPREF." + module.IOS_ID
        module.validate_profile(profile, "ABCDEFGHIJ", sha, "release-testing")
        profile["Entitlements"]["get-task-allow"] = True
        with self.assertRaises(module.DistributionError):
            module.validate_profile(profile, "ABCDEFGHIJ", sha, "release-testing")

    def test_output_parent_symlink_cannot_escape_build(self):
        with tempfile.TemporaryDirectory() as folder:
            root = pathlib.Path(folder)
            (root / "build").mkdir()
            (root / "outside").mkdir()
            (root / "build/link").symlink_to(root / "outside", target_is_directory=True)
            with self.assertRaises(module.DistributionError):
                module.reserve_output(root / "build/link/release", root)
            self.assertFalse((root / "outside/release").exists())

    def test_ios_export_does_not_enable_debugging_or_automatic_provisioning(self):
        args = module.archive_arguments("ios", pathlib.Path("/repo"), pathlib.Path("/work"),
            "ABCDEFGHIJ", "A" * 40, "0.3.0", "16", "profile-id")
        self.assertIn("PROVISIONING_PROFILE_SPECIFIER=profile-id", args)
        self.assertIn("ARCHS=arm64", args)
        self.assertNotIn("-allowProvisioningUpdates", args)
        with self.assertRaises(module.DistributionError):
            module.validate_info({"CFBundleIdentifier": module.IOS_ID,
                "CFBundleShortVersionString": "0.3.0", "CFBundleVersion": "15"}, "ios", "0.3.0", "16")

    def workflow(self, notary_status="Accepted", fail_staple=False):
        folder = tempfile.TemporaryDirectory()
        self.addCleanup(folder.cleanup)
        root = pathlib.Path(folder.name)
        output = module.reserve_output(root / "build/release", root)
        options = SimpleNamespace(platform="mac", team="ABCDEFGHIJ", identity="A" * 40,
            version="0.3.0", build_number="16", profile_uuid=None, method="release-testing",
            sparkle_bin=root / "bin", notary_profile="fixture")
        calls = []
        class Runner:
            logs = None
            def run(self, args, **kwargs):
                args = list(map(str, args)); calls.append(args)
                if args[:3] == ["git", "rev-parse", "HEAD"]: return b"synthetic-commit"
                if "-exportArchive" in args:
                    export = pathlib.Path(args[args.index("-exportPath") + 1]); (export / "DisplayWeave.app").mkdir(parents=True)
                if args[0] == "ditto": pathlib.Path(args[-1]).write_bytes(b"synthetic archive")
                if args[:3] == ["xcrun", "notarytool", "submit"]:
                    return ('{"status":"' + notary_status + '","id":"synthetic-id"}').encode()
                if fail_staple and args[:3] == ["xcrun", "stapler", "staple"]:
                    raise module.DistributionError("fixture stapler failed")
                if args[0].endswith("sign_update") and "-p" in args: return b"A" * 86 + b"=="
                return b""
        return options, Runner(), output, calls

    def test_failed_notary_cannot_sign_or_complete_artifact(self):
        for status in ["Invalid", "In Progress"]:
            options, runner, output, calls = self.workflow(status)
            with patch.object(module, "verify_app"), self.assertRaises(module.DistributionError):
                module.build_distribution(options, runner, output)
            self.assertTrue((output / "INCOMPLETE").exists())
            self.assertFalse((output / "receipt.json").exists())
            self.assertFalse((output / "DisplayWeave-macOS.zip").exists())
            self.assertFalse(any(c[0].endswith("sign_update") for c in calls))

    def test_stapler_failure_preserves_incomplete_candidate(self):
        options, runner, output, calls = self.workflow(fail_staple=True)
        with patch.object(module, "verify_app"), self.assertRaises(module.DistributionError):
            module.build_distribution(options, runner, output)
        self.assertTrue((output / "INCOMPLETE").exists())
        self.assertFalse((output / "receipt.json").exists())
        self.assertFalse(any(c[0].endswith("sign_update") for c in calls))

    def test_completed_receipt_only_after_staple_gatekeeper_and_signature(self):
        options, runner, output, calls = self.workflow()
        with patch.object(module, "verify_app"):
            artifact = module.build_distribution(options, runner, output)
        import json
        receipt = json.loads((output / "receipt.json").read_text())
        self.assertEqual(receipt["sha256"], hashlib.sha256(artifact.read_bytes()).hexdigest())
        self.assertEqual(receipt["publication"], "not uploaded")
        self.assertFalse((output / "INCOMPLETE").exists())
        names = [" ".join(call) for call in calls]
        staple = next(i for i, c in enumerate(names) if "stapler validate" in c)
        gatekeeper = next(i for i, c in enumerate(names) if "spctl --assess" in c)
        signature = next(i for i, c in enumerate(names) if "sign_update --account ed25519 --verify" in c)
        self.assertLess(staple, gatekeeper)
        self.assertLess(gatekeeper, signature)


if __name__ == "__main__":
    unittest.main()

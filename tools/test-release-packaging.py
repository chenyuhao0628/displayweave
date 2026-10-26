#!/usr/bin/env python3
"""Stable-only packaging rejects invalid coordinates before touching tools or files."""
import importlib.util
import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
spec = importlib.util.spec_from_file_location("integrity", ROOT / "tools/check-release-integrity.py")
integrity = importlib.util.module_from_spec(spec)
spec.loader.exec_module(integrity)


class ReleasePackagingTests(unittest.TestCase):
    def test_invalid_or_preview_version_stops_before_signing(self):
        for version, build in [("", "21"), ("0.3.2-rc.1", "21"), ("0.3.2-preview.1", "21"),
                               ("../output", "21"), ("0.3.2", ""), ("0.3.2", "0"), ("0.3.2", "21.1")]:
            with self.subTest(version=version, build=build), tempfile.TemporaryDirectory() as d:
                root = Path(d)
                (root / "tools").mkdir()
                shutil.copyfile(ROOT / "tools/package-release.sh", root / "tools/package-release.sh")
                (root / "tools/mac_signing.py").write_text("raise RuntimeError('SIGNING_CALLED')\n")
                env = dict(os.environ, DISPLAYWEAVE_VERSION_NAME=version, DISPLAYWEAVE_BUILD_NUMBER=build,
                           DISPLAYWEAVE_OUTPUT_DIR=str(root / "output"))
                result = subprocess.run(["bash", str(root / "tools/package-release.sh")], cwd=root,
                                        env=env, text=True, capture_output=True, timeout=10)
                self.assertEqual(result.returncode, 2)
                self.assertIn("stable X.Y.Z", result.stderr)
                self.assertNotIn("SIGNING_CALLED", result.stderr)
                self.assertFalse((root / "output").exists())

    def test_legacy_alias_preserves_arguments_and_exit_status(self):
        with tempfile.TemporaryDirectory() as d:
            root = Path(d)
            (root / "tools").mkdir()
            shutil.copyfile(ROOT / "tools/package-preview-0.1.sh", root / "tools/package-preview-0.1.sh")
            release = root / "tools/package-release.sh"
            release.write_text('#!/bin/bash\nprintf "%s\\n" "$@"\nexit 17\n')
            release.chmod(0o755)
            result = subprocess.run(["bash", str(root / "tools/package-preview-0.1.sh"), "argument with spaces"],
                                    text=True, capture_output=True, timeout=10)
            self.assertEqual(result.returncode, 17)
            self.assertEqual(result.stdout.strip(), "argument with spaces")

    def test_run_alias_preserves_arguments_and_exit_status(self):
        with tempfile.TemporaryDirectory() as d:
            root = Path(d)
            (root / "script").mkdir()
            shutil.copyfile(ROOT / "run.sh", root / "run.sh")
            runner = root / "script/build_and_run.sh"
            runner.write_text('#!/bin/bash\nprintf "%s\\n" "$@"\nexit 19\n')
            runner.chmod(0o755)
            result = subprocess.run(["bash", str(root / "run.sh"), "--verify", "argument with spaces"],
                                    text=True, capture_output=True, timeout=10)
            self.assertEqual(result.returncode, 19)
            self.assertEqual(result.stdout.splitlines(), ["--verify", "argument with spaces"])

    def test_stale_hash_in_download_table_fails_even_if_correct_hash_elsewhere(self):
        expected = {"DisplayWeave-macOS.zip": "a" * 64}
        text = f'| `DisplayWeave-macOS.zip` | `{"b" * 64}` |\nCorrect hash elsewhere: {"a" * 64}'
        self.assertEqual(len(integrity.check_table(text, expected)), 1)

    def test_matching_integrity_table_passes(self):
        expected = {"DisplayWeave-macOS.zip": "a" * 64}
        text = f'| `DisplayWeave-macOS.zip` | `{"a" * 64}` |'
        self.assertEqual(integrity.check_table(text, expected), [])


if __name__ == "__main__":
    unittest.main()

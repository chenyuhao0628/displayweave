#!/usr/bin/env python3
"""Exercise deletion boundaries using temporary repositories, never real outputs."""

import importlib.util
import tempfile
import unittest
from pathlib import Path

spec = importlib.util.spec_from_file_location("cleanup", Path(__file__).with_name("clean-workspace.py"))
cleanup = importlib.util.module_from_spec(spec)
spec.loader.exec_module(cleanup)


class CleanupTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)

    def make(self, name, content="fixture"):
        p = self.root / name
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text(content)
        return p

    def release(self, version):
        names = [*cleanup.RELEASE_FILES, f"DisplayWeave-{version}-source.tar.gz"]
        paths = [self.make(f"artifacts/releases/{version}/{name}") for name in names]
        self.make(f"artifacts/releases/{version}/SHA256SUMS.txt", "".join(f"{cleanup.sha256(p)}  {p.name}\n" for p in paths))
        return paths[0].parent

    def test_dry_run_preserves_everything(self):
        file = self.make("build/output")
        self.assertEqual(cleanup.cleanup_plan(self.root, []), [file.parent])
        self.assertTrue(file.exists())

    def test_apply_preserves_source_local_settings_and_evidence(self):
        disposable = self.make("build/nested/output")
        safe = [self.make(name) for name in ["Mac/App.swift", ".git/history", "AndroidReceiver/local.properties", "artifacts/verification/log.txt", "docs/assets/art.png"]]
        cleanup.apply_plan(self.root, cleanup.cleanup_plan(self.root, []), [])
        self.assertFalse(disposable.exists())
        self.assertTrue(all(p.exists() for p in safe))

    def test_dependencies_are_opt_in(self):
        dep = self.make("node_modules/module/index.js")
        self.assertEqual(cleanup.cleanup_plan(self.root, []), [])
        cleanup.apply_plan(self.root, cleanup.cleanup_plan(self.root, [], dependencies=True), [])
        self.assertFalse(dep.exists())

    def test_tracked_generated_path_is_rejected(self):
        self.make("build/source.swift")
        with self.assertRaisesRegex(ValueError, "tracked"):
            cleanup.cleanup_plan(self.root, ["build/source.swift"])

    def test_signing_material_is_rejected(self):
        self.make("build/private.jks")
        with self.assertRaisesRegex(ValueError, "signing material"):
            cleanup.cleanup_plan(self.root, [])

    def test_symlink_root_is_rejected(self):
        outside = self.make("outside/keep")
        (self.root / "build").symlink_to(outside.parent, target_is_directory=True)
        with self.assertRaisesRegex(ValueError, "symlink"):
            cleanup.cleanup_plan(self.root, [])
        self.assertTrue(outside.exists())

    def test_symlink_ancestor_is_rejected(self):
        target = self.make("outside/app/build/keep")
        (self.root / "AndroidReceiver").symlink_to(self.root / "outside", target_is_directory=True)
        with self.assertRaisesRegex(ValueError, "symlink"):
            cleanup.cleanup_plan(self.root, [])
        self.assertTrue(target.exists())

    def test_nested_symlink_does_not_follow_target(self):
        target = self.make("outside/keep")
        (self.root / "build").mkdir()
        (self.root / "build/link").symlink_to(target.parent, target_is_directory=True)
        cleanup.apply_plan(self.root, cleanup.cleanup_plan(self.root, []), [])
        self.assertTrue(target.exists())

    def test_release_retention_and_newer_staging(self):
        older = self.release("v0.3.0")
        latest = self.release("v0.3.1")
        future = self.release("v0.4.0")
        unknown = self.make("artifacts/releases/in-progress/notes")
        cleanup.apply_plan(self.root, cleanup.cleanup_plan(self.root, [], "v0.3.1"), [])
        self.assertFalse(older.exists())
        self.assertTrue(latest.exists() and future.exists() and unknown.exists())

    def test_corrupt_retained_release_blocks_all_deletion(self):
        latest = self.release("v0.3.1")
        (latest / "DisplayWeave-macOS.dmg").write_text("corrupt")
        output = self.make("build/output")
        with self.assertRaisesRegex(ValueError, "checksum failed"):
            cleanup.cleanup_plan(self.root, [], "v0.3.1")
        self.assertTrue(output.exists())

    def test_incomplete_manifest_is_rejected(self):
        latest = self.release("v0.3.1")
        (latest / "SHA256SUMS.txt").write_text("")
        with self.assertRaisesRegex(ValueError, "all seven"):
            cleanup.verify_release(self.root, "v0.3.1")

    def test_manifest_traversal_is_rejected(self):
        latest = self.release("v0.3.1")
        (latest / "SHA256SUMS.txt").write_text("0" * 64 + "  ../../outside\n")
        with self.assertRaisesRegex(ValueError, "Invalid"):
            cleanup.verify_release(self.root, "v0.3.1")

    def test_retained_release_symlink_is_rejected(self):
        latest = self.release("v0.3.1")
        asset = latest / "DisplayWeave-macOS.dmg"
        asset.unlink()
        asset.symlink_to(self.make("outside/dmg"))
        with self.assertRaisesRegex(ValueError, "symlink"):
            cleanup.verify_release(self.root, "v0.3.1")

    def test_reject_prerelease_or_path_as_retention_tag(self):
        for tag in ("v0.3.1-rc.1", "../../outside", "v01.0.0"):
            with self.assertRaises(ValueError):
                cleanup.verify_release(self.root, tag)


if __name__ == "__main__":
    unittest.main()

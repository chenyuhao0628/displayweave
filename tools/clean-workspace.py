#!/usr/bin/env python3
"""Preview or remove known, reproducible outputs from this checkout only."""

import argparse
import hashlib
import re
import shutil
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
GENERATED = (
    "build", "DerivedData", "build-run", "build-verify-mac", "build-verify-ios",
    "build-preview-release", "build-preview-adhoc", "site-dist", "dist-ssr",
    "AndroidReceiver/app/build", "AndroidReceiver/build", "AndroidReceiver/.gradle",
    ".pnpm-store", "tools/__pycache__",
)
RELEASE_FILES = (
    "DisplayWeave-macOS.dmg", "DisplayWeave-macOS.zip", "DisplayWeave-Android.apk",
    "DisplayWeave-iOS-unsigned-resigning-input.ipa", "appcast.xml", "android-update.json",
)
STABLE_VERSION = re.compile(r"v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\Z")


def confined(root, relative):
    """Refuse symlink roots/ancestors; rmtree never follows nested symlinks."""
    path = root / relative
    if path == root or root not in path.parents or ".." in path.parts:
        raise ValueError(f"Outside cleanup scope: {relative}")
    for ancestor in (path, *path.parents):
        if ancestor == root:
            break
        if ancestor.is_symlink():
            raise ValueError(f"Refusing symlink cleanup path: {relative}")
    return path


def sha256(path):
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def verify_release(root, version):
    if not STABLE_VERSION.fullmatch(version):
        raise ValueError("--keep-release requires a stable vX.Y.Z tag")
    path = confined(root, f"artifacts/releases/{version}")
    expected = {*RELEASE_FILES, f"DisplayWeave-{version}-source.tar.gz"}
    manifest = confined(root, f"artifacts/releases/{version}/SHA256SUMS.txt")
    rows = manifest.read_text().splitlines()
    checksums = {}
    for row in rows:
        match = re.fullmatch(r"([a-fA-F0-9]{64}) [ *]([^/\\]+)", row)
        if not match or match[2] in checksums or match[2] not in expected:
            raise ValueError(f"Invalid or duplicate release checksum entry: {row!r}")
        checksums[match[2]] = match[1].lower()
    if set(checksums) != expected:
        raise ValueError("Retained release must contain all seven checksummed assets")
    # Browsing the retained folder in Finder can create this harmless metadata.
    if {p.name for p in path.iterdir() if p.name != ".DS_Store"} != expected | {"SHA256SUMS.txt"}:
        raise ValueError("Retained release contains missing or unexpected files")
    for name, digest in checksums.items():
        asset = confined(root, f"artifacts/releases/{version}/{name}")
        if not asset.is_file() or sha256(asset) != digest:
            raise ValueError(f"Retained release checksum failed: {name}")
    return path


def cleanup_plan(root, tracked, keep_release=None, dependencies=False):
    names = list(GENERATED)
    if dependencies:
        names.append("node_modules")
    if keep_release:
        kept = verify_release(root, keep_release)
        version = tuple(map(int, STABLE_VERSION.fullmatch(keep_release).groups()))
        for path in sorted(kept.parent.iterdir()):
            if path == kept:
                continue
            match = STABLE_VERSION.fullmatch(path.name)
            # Unknown folders and future staging outputs are never inferred obsolete.
            if match and tuple(map(int, match.groups())) < version:
                names.append(path.relative_to(root).as_posix())
    plan = []
    for name in names:
        path = confined(root, name)
        if not path.exists():
            continue
        if any(f == name or f.startswith(name + "/") for f in tracked):
            raise ValueError(f"Refusing to delete tracked content: {name}")
        # A mistakenly stored key is not a reproducible build output.
        if path.is_dir():
            for item in path.rglob("*"):
                if not item.is_symlink() and item.suffix.lower() in {".jks", ".keystore", ".p12", ".p8", ".key"}:
                    raise ValueError(f"Move signing material outside generated output first: {item.relative_to(root)}")
        plan.append(path)
    return plan


def size_bytes(path):
    if path.is_symlink():
        return 0
    if path.is_file():
        return path.stat().st_size
    return sum(p.stat().st_size for p in path.rglob("*") if not p.is_symlink() and p.is_file())


def apply_plan(root, plan, tracked):
    # Recheck every path before mutating anything.
    for path in plan:
        name = path.relative_to(root).as_posix()
        confined(root, name)
        if any(f == name or f.startswith(name + "/") for f in tracked):
            raise ValueError(f"Refusing to delete tracked content: {name}")
    for path in plan:
        if path.is_dir():
            shutil.rmtree(path)
        else:
            path.unlink()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--apply", action="store_true", help="delete the displayed generated paths; default is a dry run")
    parser.add_argument("--dependencies", action="store_true", help="also remove node_modules (restore with pnpm install --frozen-lockfile)")
    parser.add_argument("--keep-release", metavar="vX.Y.Z", help="verify this complete local release and prune older stable release folders; confirm the published tag first")
    args = parser.parse_args()
    try:
        actual_root = subprocess.check_output(["git", "-C", str(ROOT), "rev-parse", "--show-toplevel"], text=True).strip()
        if Path(actual_root).resolve() != ROOT:
            raise ValueError("Run this tool from its own Git checkout")
        tracked = subprocess.check_output(["git", "-C", str(ROOT), "ls-files", "-z"], text=True).split("\0")
        plan = cleanup_plan(ROOT, tracked, args.keep_release, args.dependencies)
        total = 0
        for path in plan:
            size = size_bytes(path)
            total += size
            print(f"{size / 1024**2:9.1f} MiB  {path.relative_to(ROOT)}")
        print(f"{'Remove' if args.apply else 'Dry run'}: {len(plan)} paths, {total / 1024**2:.1f} MiB logical file bytes")
        if args.apply:
            apply_plan(ROOT, plan, tracked)
            if args.keep_release:
                verify_release(ROOT, args.keep_release)
            print("Cleanup complete. Release evidence, source, Git history and external signing material retained.")
        else:
            print("Stop project builds/dev servers before applying. Re-run with --apply to delete these paths.")
    except (OSError, ValueError, subprocess.CalledProcessError) as error:
        parser.exit(1, f"Cleanup stopped: {error}\n")


if __name__ == "__main__":
    main()

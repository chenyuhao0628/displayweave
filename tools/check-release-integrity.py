#!/usr/bin/env python3
"""Cross-check each active download table, not just a hash somewhere in docs."""
import hashlib
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
ASSETS = ("DisplayWeave-Android.apk", "DisplayWeave-macOS.zip", "DisplayWeave-macOS.dmg",
          "DisplayWeave-iOS-unsigned-resigning-input.ipa", "appcast.xml", "android-update.json")


def check_table(text, expected):
    errors = []
    for name, digest in expected.items():
        rows = [line for line in text.splitlines() if line.startswith("|") and f"`{name}`" in line]
        if len(rows) != 1 or re.findall(r"`([0-9a-f]{64})`", rows[0]) != [digest]:
            errors.append(f"{name}: missing, duplicate or stale SHA-256")
    return errors


def check_public_feeds(root, expected):
    errors = []
    for name in ("appcast.xml", "android-update.json"):
        feed_path = root / "public" / name
        if not feed_path.is_file():
            errors.append(f"public/{name}: missing feed file")
            continue
        actual = hashlib.sha256(feed_path.read_bytes()).hexdigest()
        if actual != expected[name]:
            errors.append(f"public/{name}: SHA-256 {actual} != expected {expected[name]}")
    android_feed = root / "public" / "android-update.json"
    if android_feed.is_file():
        payload = json.loads(android_feed.read_text())
        if payload.get("sha256") != expected["DisplayWeave-Android.apk"]:
            errors.append("public/android-update.json: embedded APK sha256 mismatch")
    return errors


def check_local_manifest(root, tag, expected):
    manifest = root / "artifacts" / "releases" / tag / "SHA256SUMS.txt"
    if not manifest.is_file():
        return []
    entries = {}
    for line in manifest.read_text().splitlines():
        parts = line.strip().split()
        if len(parts) == 2:
            entries[parts[1]] = parts[0]
    errors = []
    for name, digest in expected.items():
        if entries.get(name) != digest:
            errors.append(f"{manifest.relative_to(root)}: {name} hash mismatch")
    source_name = f"DisplayWeave-{tag}-source.tar.gz"
    if not re.fullmatch(r"[0-9a-f]{64}", entries.get(source_name, "")):
        errors.append(f"{manifest.relative_to(root)}: missing valid {source_name} SHA-256")
    return errors


def main():
    tag, *hashes = sys.argv[1:]
    if not re.fullmatch(r"v\d+\.\d+\.\d+", tag) or len(hashes) != len(ASSETS):
        sys.exit("Expected a stable tag and six SHA-256 values from check-release-links.sh")
    expected = dict(zip(ASSETS, hashes))
    errors = []
    for language in ("", ".zh-CN"):
        for stem, values in [("current", dict(list(expected.items())[:4])), (tag, expected)]:
            path = ROOT / f"docs/releases/{stem}{language}.md"
            errors += [f"{path.relative_to(ROOT)}: {message}" for message in check_table(path.read_text(), values)]
    errors += check_public_feeds(ROOT, expected)
    errors += check_local_manifest(ROOT, tag, expected)
    if errors:
        sys.exit("\n".join(errors))
    print("Release integrity tables PASS: current downloads and release notes in both languages")


if __name__ == "__main__":
    main()

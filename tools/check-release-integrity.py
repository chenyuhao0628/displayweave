#!/usr/bin/env python3
"""Cross-check each active download table, not just a hash somewhere in docs."""
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
    if errors:
        sys.exit("\n".join(errors))
    print("Release integrity tables PASS: current downloads and release notes in both languages")


if __name__ == "__main__":
    main()

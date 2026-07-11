#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"

tag="v0.1.0-preview.2"
assets=(
  "DisplayWeave-Preview-0.1-Android.apk"
  "DisplayWeave-Preview-0.1-macOS.zip"
  "DisplayWeave-Preview-0.1-iOS-unsigned-resigning-input.ipa"
  "SHA256SUMS.txt"
)
sources=(src README.md README.zh-CN.md docs/release-notes-preview-0.1.md)

grep -R -Fq "$tag" "${sources[@]}" || {
  echo "missing release tag: $tag" >&2
  exit 1
}

for asset in "${assets[@]}"; do
  grep -R -Fq "$asset" "${sources[@]}" || {
    echo "missing release asset reference: $asset" >&2
    exit 1
  }
done

if grep -R -E 'v0\.1\.0-preview\.1|DisplayWeave-Android-debug\.apk|DisplayWeave-iOS-Simulator-development-preview\.zip' "${sources[@]}"; then
  echo "obsolete Preview 1 release reference found" >&2
  exit 1
fi

echo "release-link check passed: $tag and ${#assets[@]} assets"

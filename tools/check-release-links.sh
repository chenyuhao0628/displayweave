#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"

tag="v0.2.0-preview.3"
assets=(
  "DisplayWeave-Android.apk"
  "DisplayWeave-macOS.zip"
  "DisplayWeave-macOS.dmg"
  "DisplayWeave-Preview-0.1-iOS-unsigned-resigning-input.ipa"
  "appcast.xml"
  "android-update.json"
  "SHA256SUMS.txt"
)
hashes=(
  "32cade719d825d3f3562483cb72b9a4d65223e4b2518d54389ff2d661a1742ae"
  "68b3737f09f8d02da135aef89167896aa4057d453d65fa20861e2ae58a142a29"
  "98356346793932bd494a31585ff7ca788b880bd62cd6b8e2762aadc8ff0541c1"
  "7eb93eedd24e44bbabccb38ab145a2e2122e4c53bd52dbe8e9d2b3d08e21eb16"
  "3606e4f32678319f1bcea1e94e97bcba1a1171a6810ed935be3b00264f4795c8"
  "90adbfe6345de384c8541b986673cae28c256a6cef8017e000fb93ff7cfdbf70"
)
sources=(
  src index.html README.md README.zh-CN.md
  AndroidReceiver/README.md AndroidReceiver/README.zh-CN.md
  docs/development-preview.md docs/development-preview.zh-CN.md
  docs/release-notes-v0.2.0-preview.3.md
  docs/release-notes-v0.2.0-preview.3.zh-CN.md
  docs/release-checklist.md docs/release-checklist.zh-CN.md
  docs/automatic-updates.md docs/automatic-updates.zh-CN.md
)

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

for hash in "${hashes[@]}"; do
  grep -R -Fq "$hash" "${sources[@]}" || {
    echo "missing current release SHA-256: $hash" >&2
    exit 1
  }
done

release_url="https://github.com/chenyuhao0628/displayweave/releases/tag/$tag"
mac_feed="https://chenyuhao0628.github.io/displayweave/appcast.xml"
android_feed="https://chenyuhao0628.github.io/displayweave/android-update.json"
for url in "$release_url" "$mac_feed" "$android_feed"; do
  grep -R -Fq "$url" "${sources[@]}" || {
    echo "missing current release URL: $url" >&2
    exit 1
  }
done

if grep -R -E 'v0\.1\.0-preview\.2|DisplayWeave-Preview-0\.1-(macOS|Android)|v0\.1\.0-preview\.1|DisplayWeave-Android-debug\.apk|DisplayWeave-iOS-Simulator-development-preview\.zip' "${sources[@]}"; then
  echo "obsolete active release reference found" >&2
  exit 1
fi

workflow=".github/workflows/release.yml"
workflow_contract=(
  "release_tag"
  "SPARKLE_PRIVATE_KEY"
  "DISPLAYWEAVE_ANDROID_KEYSTORE_BASE64"
  "DISPLAYWEAVE_ANDROID_STORE_PASSWORD"
  "DISPLAYWEAVE_ANDROID_KEY_ALIAS"
  "DISPLAYWEAVE_ANDROID_KEY_PASSWORD"
  "Mac/OpenSidecarMacAdHoc.entitlements"
  "DisplayWeave-macOS.zip"
  "DisplayWeave-macOS.dmg"
  "DisplayWeave-Android.apk"
  "appcast.xml"
  "android-update.json"
  "apksigner"
  "CODE_SIGNING_ALLOWED=NO"
  "if: always()"
  "actions/deploy-pages@v4"
  "python3 -m venv"
  "displayweave-appcast-input"
  "needs.build_updates.result == 'success'"
)
for marker in "${workflow_contract[@]}"; do
  grep -Fq "$marker" "$workflow" || {
    echo "release workflow is missing update contract marker: $marker" >&2
    exit 1
  }
done

if grep -Fq '${{ runner.temp }}' "$workflow"; then
  echo "release workflow uses runner.temp before the runner context exists" >&2
  exit 1
fi

if grep -Eiq 'MATCH_|Developer ID|notari[sz]|TestFlight|fastlane' "$workflow"; then
  echo "release workflow still depends on credential-bound Apple publication" >&2
  exit 1
fi

echo "release-link check passed: $tag, ${#assets[@]} assets, and automatic-update workflow"

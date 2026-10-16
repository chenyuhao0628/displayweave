#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"

tag="v0.3.0-preview.1"
assets=(
  "DisplayWeave-Android.apk"
  "DisplayWeave-macOS.zip"
  "DisplayWeave-macOS.dmg"
  "DisplayWeave-Preview-0.1-iOS-unsigned-resigning-input.ipa"
  "appcast.xml"
  "android-update.json"
  "DisplayWeave-v0.3.0-preview.1-source.tar.gz"
  "SHA256SUMS.txt"
)
hashes=(
  "72e158c825f8ba16ac14677312167ee83a72aa6590b089c788dc54521c1b3057"
  "c4cb42af68f0479d8fc884ae3c631655a24dca5ce5000ed9d2b3e81214e88cc7"
  "820bad434a200cba3e7ef2d7acad0b3f052fcef6c479d57a1d8efb5bb1d5ac29"
  "ba881f0c23e3a992ce0ca615ee245b8c638765b06e65dac0a9b3f913d51db965"
  "159a629e28cfb739479c86471ad521d967414e7835764a1e536e623cdcb73ce6"
  "0a41d1c4635bf94803e946e3bad133172a7de319831daf9e0ab0c6ec8c3ee452"
)
sources=(
  src index.html README.md README.zh-CN.md
  AndroidReceiver/README.md AndroidReceiver/README.zh-CN.md
  docs/development-preview.md docs/development-preview.zh-CN.md
  docs/release-notes-v0.3.0-preview.1.md
  docs/release-notes-v0.3.0-preview.1.zh-CN.md
  docs/release-checklist.md docs/release-checklist.zh-CN.md
  docs/automatic-updates.md docs/automatic-updates.zh-CN.md
)

grep -R -Fq "$tag" "${sources[@]}" || {
  echo "missing release tag: $tag" >&2
  exit 1
}

grep -Fq "export const releaseTag = \"$tag\"" src/content.ts || {
  echo "site releaseTag does not match current release: $tag" >&2
  exit 1
}
grep -Fq "\"softwareVersion\": \"${tag#v}\"" index.html || {
  echo "site structured-data version does not match current release: $tag" >&2
  exit 1
}
grep -Fq "\"versionName\": \"${tag#v}\"" public/android-update.json || {
  echo "checked-in Android feed does not match current release: $tag" >&2
  exit 1
}
grep -Fq "<sparkle:shortVersionString>${tag#v}</sparkle:shortVersionString>" public/appcast.xml || {
  echo "checked-in Sparkle feed does not match current release: $tag" >&2
  exit 1
}

release_base="https://github.com/chenyuhao0628/displayweave/releases/download/$tag"
grep -Fq 'export const releaseBase = `https://github.com/chenyuhao0628/displayweave/releases/download/${releaseTag}`' src/content.ts || {
  echo "site download base does not use GitHub Releases: $release_base" >&2
  exit 1
}
grep -Fq "<enclosure url=\"$release_base/DisplayWeave-macOS.zip\"" public/appcast.xml || {
  echo "Sparkle enclosure does not use GitHub Releases" >&2
  exit 1
}
grep -Fq '"apkUrl": "'"$release_base"'/DisplayWeave-Android.apk"' public/android-update.json || {
  echo "Android APK URL does not use GitHub Releases" >&2
  exit 1
}
if grep -Fq 'apkFallbackUrl' public/android-update.json; then
  echo "Android feed must not declare a fallback download source" >&2
  exit 1
fi

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

release_url="https://github.com/chenyuhao0628/displayweave/releases"
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

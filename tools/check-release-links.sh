#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"

tag="v0.3.1"
assets=(
  "DisplayWeave-Android.apk"
  "DisplayWeave-macOS.zip"
  "DisplayWeave-macOS.dmg"
  "DisplayWeave-iOS-unsigned-resigning-input.ipa"
  "appcast.xml"
  "android-update.json"
  "DisplayWeave-v0.3.1-source.tar.gz"
  "SHA256SUMS.txt"
)
hashes=(
  "3826c8ad64ae5924e78396a916f310adeb4bbef393f20799eca52b04de21716f"
  "d567e1081f3bcf974a280935628083d99311c074a8a1ee80b0d9c1223663f8ca"
  "50759c579713ee637cacf0106c4d8656dafaa8e4c1866bcb36f0a326c3b405c0"
  "7a1dcae8d11449f7c64b08a1aa8b362bc6849d94353c9bc080ee30ad0803da3c"
  "3824a5626463db280f207f01afa01b7f5ac2be964a7128ce6ec1c8fa224f57eb"
  "72e0e3517b8718ebfa66180165ed0e0840d587b0e106d0d6ffa8776450239f41"
)
sources=(
  src index.html README.md README.zh-CN.md
  AndroidReceiver/README.md AndroidReceiver/README.zh-CN.md
  docs/releases/current.md docs/releases/current.zh-CN.md
  docs/releases/v0.3.1.md
  docs/releases/v0.3.1.zh-CN.md
  docs/releases/release-checklist.md docs/releases/release-checklist.zh-CN.md
  docs/releases/automatic-updates.md docs/releases/automatic-updates.zh-CN.md
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
  "Mac/OpenSidecarMac.entitlements"
  "mac_signing.py xcode-settings"
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

python3 tools/check-release-integrity.py "$tag" "${hashes[@]}"
echo "release-link check passed: $tag, ${#assets[@]} assets, and automatic-update workflow"

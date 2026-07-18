#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"

tag="v0.2.1-p6"
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
  "123fea1468335f8412b0f8620623c3c9fa681b36ef5e9e3190e3b1ec2c812083"
  "d1b5bef839322f34d0cd31067aa78776108a6014233677869fb394b3bc12b44a"
  "441651dcb54304f2ec147ebdc35db7808d92812631496b99e17f41394f31c691"
  "7430569bb68db065a056f827b0538eca780a65455dbed3ce0d69e3503c0320a8"
  "bf1429a9774c2a2661136832902bc4e032a32b0b83108ea3b567ff206dd7df0c"
  "4fc43c7606b40f786d21872ab3dd1243ecd79308237e75cb3aaff1e84acdb377"
)
sources=(
  src index.html README.md README.zh-CN.md
  AndroidReceiver/README.md AndroidReceiver/README.zh-CN.md
  docs/development-preview.md docs/development-preview.zh-CN.md
  docs/release-notes-v0.2.1-p6.md
  docs/release-notes-v0.2.1-p6.zh-CN.md
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

mirror_base="https://downloads.urlget.cyou/releases/$tag"
grep -Fq 'export const releaseBase = `https://downloads.urlget.cyou/releases/${releaseTag}`' src/content.ts || {
  echo "site download base does not use the Cloudflare mirror: $mirror_base" >&2
  exit 1
}
grep -Fq "<enclosure url=\"$mirror_base/DisplayWeave-macOS.zip\"" public/appcast.xml || {
  echo "Sparkle enclosure does not use the Cloudflare mirror" >&2
  exit 1
}
grep -Fq '"apkUrl": "'"$mirror_base"'/DisplayWeave-Android.apk"' public/android-update.json || {
  echo "Android primary APK URL does not use the Cloudflare mirror" >&2
  exit 1
}
grep -Fq '"apkFallbackUrl": "https://github.com/chenyuhao0628/displayweave/releases/download/'"$tag"'/DisplayWeave-Android.apk"' public/android-update.json || {
  echo "Android fallback APK URL does not use the matching GitHub Release" >&2
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

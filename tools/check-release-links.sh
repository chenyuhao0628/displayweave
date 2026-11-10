#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"

tag="v0.3.5"
assets=(
  "DisplayWeave-Android.apk"
  "DisplayWeave-macOS.zip"
  "DisplayWeave-macOS.dmg"
  "DisplayWeave-iOS-unsigned-resigning-input.ipa"
  "appcast.xml"
  "android-update.json"
  "DisplayWeave-v0.3.5-source.tar.gz"
  "SHA256SUMS.txt"
)
hashes=(
  "25387fafb821321797a3d6a4ef79101ce89225b613edb63c9e65f642912e1db6"
  "eb88bf026dba990b0f1d3bc89dfcd7963884be79f6409b33206d43b8675aa6bc"
  "ddcbe28b170d2efa9f160ad1d376986cbf137f0a5af7bcba9352266db2a7ec70"
  "b79c1bbbe23c8a07b57df9be52d808ac68aee9471edd716251c81681253560b1"
  "894dd68e7ad5cf4496f434544d903ecf83208e4a61a49f42c3159782d2694487"
  "b69f767496ebbfdc7e7a75c54d15b78ddd7f77738cbd3056509b9009175d75ba"
)
sources=(
  src index.html README.md README.zh-CN.md
  AndroidReceiver/README.md AndroidReceiver/README.zh-CN.md
  docs/releases/current.md docs/releases/current.zh-CN.md
  docs/releases/v0.3.5.md
  docs/releases/v0.3.5.zh-CN.md
  docs/releases/release-checklist.md docs/releases/release-checklist.zh-CN.md
  docs/releases/automatic-updates.md docs/releases/automatic-updates.zh-CN.md
)

tag_sources=(
  src README.md README.zh-CN.md
  AndroidReceiver/README.md AndroidReceiver/README.zh-CN.md
  docs/releases/current.md docs/releases/current.zh-CN.md
  "docs/releases/$tag.md"
  "docs/releases/$tag.zh-CN.md"
  docs/releases/release-checklist.md docs/releases/release-checklist.zh-CN.md
  docs/releases/automatic-updates.md docs/releases/automatic-updates.zh-CN.md
)

for source in "${tag_sources[@]}"; do
  grep -R -Fq "$tag" "$source" || {
    echo "missing release tag $tag in $source" >&2
    exit 1
  }
done

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
grep -Fq "\"sha256\": \"${hashes[0]}\"" public/android-update.json || {
  echo "checked-in Android feed APK sha256 does not match current release: ${hashes[0]}" >&2
  exit 1
}

appcast_sha="$(shasum -a 256 public/appcast.xml | awk '{ print $1 }')"
[[ "$appcast_sha" == "${hashes[4]}" ]] || {
  echo "public/appcast.xml SHA-256 ($appcast_sha) does not match release table (${hashes[4]})" >&2
  exit 1
}
android_feed_sha="$(shasum -a 256 public/android-update.json | awk '{ print $1 }')"
[[ "$android_feed_sha" == "${hashes[5]}" ]] || {
  echo "public/android-update.json SHA-256 ($android_feed_sha) does not match release table (${hashes[5]})" >&2
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

asset_docs=(
  docs/releases/current.md
  docs/releases/current.zh-CN.md
  "docs/releases/$tag.md"
  "docs/releases/$tag.zh-CN.md"
)
for doc in "${asset_docs[@]}"; do
  for asset in "${assets[@]}"; do
    grep -Fq "$asset" "$doc" || {
      echo "missing release asset reference $asset in $doc" >&2
      exit 1
    }
  done
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
  "DISPLAYWEAVE_MAC_BASELINE_APP"
  "Mac/OpenSidecarMac.entitlements"
  "mac_signing.py xcode-settings"
  "DisplayWeave-macOS.zip"
  "DisplayWeave-macOS.dmg"
  "DisplayWeave-Android.apk"
  "appcast.xml"
  "android-update.json"
  "-source.tar.gz"
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

#!/bin/bash
set -euo pipefail

PINNED_CERT="89805f045800ea18b56b84b32e8e31b1710a3c7bf3c85fda54d260d1fc6d589d"

verify_android_metadata() {
  local feed="$1" apk="$2" version="$3" build="$4" certificate="$5"
  FEED="$feed" APK="$apk" EXPECTED_VERSION="$version" EXPECTED_BUILD="$build" \
  EXPECTED_CERTIFICATE="$certificate" ruby <<'RUBY'
require "json"
require "digest"
require "uri"

feed = JSON.parse(File.read(ENV.fetch("FEED")))
apk = ENV.fetch("APK")
fail "schemaVersion mismatch" unless feed["schemaVersion"] == 1
fail "packageName mismatch" unless feed["packageName"] == "app.opendisplay.android"
fail "versionCode mismatch" unless feed["versionCode"] == Integer(ENV.fetch("EXPECTED_BUILD"))
fail "versionName mismatch" unless feed["versionName"] == ENV.fetch("EXPECTED_VERSION")
fail "minimumSdk mismatch" unless feed["minimumSdk"] == 26
url = URI.parse(feed.fetch("apkUrl"))
fail "APK URL must use HTTPS" unless url.scheme == "https"
fail "APK URL filename mismatch" unless url.path.end_with?("/DisplayWeave-Android.apk")
fail "APK size mismatch" unless feed["apkSize"] == File.size(apk)
fail "APK SHA-256 mismatch" unless feed["sha256"] == Digest::SHA256.file(apk).hexdigest
fail "APK signer fingerprint mismatch" unless feed["signingCertificateSha256"] == ENV.fetch("EXPECTED_CERTIFICATE")
notes = URI.parse(feed.fetch("releaseNotesUrl"))
fail "release notes URL must use HTTPS" unless notes.scheme == "https"
RUBY
}

if [[ "${1:-}" == "--android-metadata" ]]; then
  [[ $# -eq 6 ]] || { echo "usage: $0 --android-metadata FEED APK VERSION BUILD CERT" >&2; exit 64; }
  verify_android_metadata "$2" "$3" "$4" "$5" "$6"
  exit 0
fi

[[ $# -eq 1 ]] || { echo "usage: $0 RELEASE_DIRECTORY" >&2; exit 64; }
directory="$1"
version="${DISPLAYWEAVE_VERSION_NAME:?DISPLAYWEAVE_VERSION_NAME is required}"
build="${DISPLAYWEAVE_BUILD_NUMBER:?DISPLAYWEAVE_BUILD_NUMBER is required}"
mac_zip="$directory/DisplayWeave-macOS.zip"
android_apk="$directory/DisplayWeave-Android.apk"
appcast="$directory/appcast.xml"
android_feed="$directory/android-update.json"
checksums="$directory/SHA256SUMS.txt"

for file in "$mac_zip" "$android_apk" "$appcast" "$android_feed" "$checksums"; do
  [[ -f "$file" ]] || { echo "Missing release artifact: $file" >&2; exit 2; }
done
unzip -tq "$mac_zip" >/dev/null
grep -q 'sparkle:edSignature=' "$appcast" || { echo "Appcast lacks an EdDSA signature." >&2; exit 3; }
grep -q 'DisplayWeave-macOS.zip' "$appcast" || { echo "Appcast archive filename mismatch." >&2; exit 3; }

temporary="$(mktemp -d "${TMPDIR:-/tmp}/displayweave-update-verify.XXXXXX")"
trap 'rm -rf "$temporary"' EXIT
unzip -q "$mac_zip" -d "$temporary"
mac_plist="$(find "$temporary" -maxdepth 3 -path '*/DisplayWeave.app/Contents/Info.plist' -print -quit)"
[[ -n "$mac_plist" ]] || { echo "Mac archive has no app Info.plist." >&2; exit 3; }
[[ "$(plutil -extract CFBundleShortVersionString raw "$mac_plist")" == "$version" ]] \
  || { echo "Mac version name mismatch." >&2; exit 3; }
[[ "$(plutil -extract CFBundleVersion raw "$mac_plist")" == "$build" ]] \
  || { echo "Mac build number mismatch." >&2; exit 3; }

verify_android_metadata "$android_feed" "$android_apk" "$version" "$build" "$PINNED_CERT"
SDK_ROOT="${ANDROID_SDK_ROOT:-${ANDROID_HOME:-$HOME/Library/Android/sdk}}"
APKSIGNER="${APKSIGNER:-$SDK_ROOT/build-tools/36.1.0/apksigner}"
AAPT="${AAPT:-$SDK_ROOT/build-tools/36.1.0/aapt}"
certificate="$($APKSIGNER verify --print-certs "$android_apk" \
  | sed -n 's/^Signer #1 certificate SHA-256 digest: //p' | head -1 \
  | tr '[:upper:]' '[:lower:]' | tr -d ':[:space:]')"
[[ "$certificate" == "$PINNED_CERT" ]] || { echo "Android APK signer mismatch." >&2; exit 4; }
badging="$($AAPT dump badging "$android_apk" | head -1)"
[[ "$badging" == *"versionCode='$build'"* ]] || { echo "Android APK version code mismatch." >&2; exit 4; }
[[ "$badging" == *"versionName='$version'"* ]] || { echo "Android APK version name mismatch." >&2; exit 4; }

(cd "$directory" && shasum -a 256 -c "$(basename "$checksums")")
echo "Update release verification PASS"

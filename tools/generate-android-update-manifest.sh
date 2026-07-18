#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APK="${DISPLAYWEAVE_ANDROID_APK:-$ROOT_DIR/build/update-release/DisplayWeave-Android.apk}"
OUTPUT="${DISPLAYWEAVE_ANDROID_FEED_OUTPUT:-$ROOT_DIR/build/update-release/android-update.json}"
VERSION_NAME="${DISPLAYWEAVE_VERSION_NAME:?DISPLAYWEAVE_VERSION_NAME is required}"
BUILD_NUMBER="${DISPLAYWEAVE_BUILD_NUMBER:?DISPLAYWEAVE_BUILD_NUMBER is required}"
RELEASE_TAG="${DISPLAYWEAVE_RELEASE_TAG:?DISPLAYWEAVE_RELEASE_TAG is required}"
RELEASE_BASE_URL="${DISPLAYWEAVE_RELEASE_BASE_URL:?DISPLAYWEAVE_RELEASE_BASE_URL is required}"
FALLBACK_BASE_URL="${DISPLAYWEAVE_RELEASE_FALLBACK_BASE_URL:-}"
PUBLISHED_AT="${DISPLAYWEAVE_PUBLISHED_AT:?DISPLAYWEAVE_PUBLISHED_AT is required}"
PINNED_CERT="89805f045800ea18b56b84b32e8e31b1710a3c7bf3c85fda54d260d1fc6d589d"
SDK_ROOT="${ANDROID_SDK_ROOT:-${ANDROID_HOME:-$HOME/Library/Android/sdk}}"
APKSIGNER="${APKSIGNER:-$SDK_ROOT/build-tools/36.1.0/apksigner}"

test -f "$APK"
test -x "$APKSIGNER"
mkdir -p "$(dirname "$OUTPUT")"

certificate="$($APKSIGNER verify --print-certs "$APK" \
  | sed -n 's/^Signer #1 certificate SHA-256 digest: //p' \
  | head -1 \
  | tr '[:upper:]' '[:lower:]' \
  | tr -d ':[:space:]')"
if [[ "$certificate" != "$PINNED_CERT" ]]; then
  echo "Android signer fingerprint does not match the pinned update key." >&2
  exit 2
fi

size="$(stat -f %z "$APK" 2>/dev/null || stat -c %s "$APK")"
sha256="$(shasum -a 256 "$APK" | awk '{print $1}')"
temporary="$(mktemp "$(dirname "$OUTPUT")/.android-update.XXXXXX")"
trap 'rm -f "$temporary"' EXIT

APK_SIZE="$size" APK_SHA256="$sha256" APK_CERTIFICATE="$certificate" \
DISPLAYWEAVE_RELEASE_FALLBACK_BASE_URL="$FALLBACK_BASE_URL" \
OUTPUT_FILE="$temporary" ruby <<'RUBY'
require "json"
require "time"

base = ENV.fetch("DISPLAYWEAVE_RELEASE_BASE_URL").sub(%r{/+$}, "")
tag = ENV.fetch("DISPLAYWEAVE_RELEASE_TAG")
published = Time.iso8601(ENV.fetch("DISPLAYWEAVE_PUBLISHED_AT")).utc.iso8601
feed = {
  schemaVersion: 1,
  packageName: "app.opendisplay.android",
  versionCode: Integer(ENV.fetch("DISPLAYWEAVE_BUILD_NUMBER")),
  versionName: ENV.fetch("DISPLAYWEAVE_VERSION_NAME"),
  minimumSdk: 26,
  apkUrl: "#{base}/#{tag}/DisplayWeave-Android.apk",
  apkSize: Integer(ENV.fetch("APK_SIZE")),
  sha256: ENV.fetch("APK_SHA256"),
  signingCertificateSha256: ENV.fetch("APK_CERTIFICATE"),
  publishedAt: published,
  releaseNotesUrl: "https://github.com/chenyuhao0628/displayweave/releases/tag/#{tag}"
}
fallback = ENV.fetch("DISPLAYWEAVE_RELEASE_FALLBACK_BASE_URL", "").sub(%r{/+$}, "")
feed[:apkFallbackUrl] = "#{fallback}/#{tag}/DisplayWeave-Android.apk" unless fallback.empty?
File.write(ENV.fetch("OUTPUT_FILE"), JSON.pretty_generate(feed) + "\n")
RUBY

mv "$temporary" "$OUTPUT"
chmod 644 "$OUTPUT"
trap - EXIT
echo "Generated $OUTPUT"

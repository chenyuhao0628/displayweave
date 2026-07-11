#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
OUT_DIR="$ROOT_DIR/build/preview-0.1"
MAC_DERIVED="$ROOT_DIR/build/preview-0.1-mac-derived"
ANDROID_APK="$ROOT_DIR/AndroidReceiver/app/build/outputs/apk/release/app-release.apk"
APKSIGNER="${ANDROID_SDK_ROOT:-${ANDROID_HOME:-$HOME/Library/Android/sdk}}/build-tools/36.1.0/apksigner"

mkdir -p "$OUT_DIR"
cd "$ROOT_DIR"
./generate.sh

# Preview builds are intentionally ad-hoc. With Hardened Runtime and embedded
# Sparkle, an ad-hoc app has no Team ID for library validation, so use the
# preview-only entitlement. Production Developer ID builds must keep using
# Mac/OpenSidecarMac.entitlements and must be notarized.
xcodebuild -quiet \
  -project OpenSidecar.xcodeproj \
  -scheme OpenSidecarMac \
  -configuration Release \
  -derivedDataPath "$MAC_DERIVED" \
  -clonedSourcePackagesDirPath "$MAC_DERIVED/SourcePackages" \
  MARKETING_VERSION=0.1.0 \
  CURRENT_PROJECT_VERSION=1 \
  CODE_SIGN_ENTITLEMENTS=Mac/OpenSidecarMacAdHoc.entitlements \
  CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO \
  build

MAC_APP="$MAC_DERIVED/Build/Products/Release/DisplayWeave.app"
codesign --verify --deep --strict --verbose=2 "$MAC_APP"
ditto -c -k --sequesterRsrc --keepParent \
  "$MAC_APP" "$OUT_DIR/DisplayWeave-Preview-0.1-macOS.zip"

cd "$ROOT_DIR/AndroidReceiver"
./gradlew clean test assembleRelease

if [[ ! -f "$ANDROID_APK" ]]; then
  echo "Android release APK is unsigned; refusing to package it." >&2
  echo "Set DISPLAYWEAVE_ANDROID_KEYSTORE, DISPLAYWEAVE_ANDROID_STORE_PASSWORD," >&2
  echo "DISPLAYWEAVE_ANDROID_KEY_ALIAS, and DISPLAYWEAVE_ANDROID_KEY_PASSWORD." >&2
  exit 2
fi

"$APKSIGNER" verify --verbose --print-certs "$ANDROID_APK"
cp "$ANDROID_APK" "$OUT_DIR/DisplayWeave-Preview-0.1-Android.apk"

cd "$OUT_DIR"
shasum -a 256 \
  DisplayWeave-Preview-0.1-macOS.zip \
  DisplayWeave-Preview-0.1-Android.apk > SHA256SUMS.txt

echo "DisplayWeave Preview 0.1 artifacts:"
ls -lh "$OUT_DIR"

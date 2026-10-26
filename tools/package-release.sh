#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
MAC_DERIVED="$ROOT_DIR/build/package/mac"
IOS_DERIVED="$ROOT_DIR/build/package/ios"
ANDROID_APK="$ROOT_DIR/AndroidReceiver/app/build/outputs/apk/release/app-release.apk"
VERSION_NAME="${DISPLAYWEAVE_VERSION_NAME:-}"
BUILD_NUMBER="${DISPLAYWEAVE_BUILD_NUMBER:-}"
OUT_DIR="${DISPLAYWEAVE_OUTPUT_DIR:-$ROOT_DIR/artifacts/releases/v$VERSION_NAME}"
if [[ ! "$VERSION_NAME" =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]] ||
   [[ ! "$BUILD_NUMBER" =~ ^[1-9][0-9]*$ ]]; then
  echo "Set DISPLAYWEAVE_VERSION_NAME to a stable X.Y.Z version and DISPLAYWEAVE_BUILD_NUMBER to a positive integer. See docs/releases/local-release.md." >&2
  exit 2
fi
MAC_DMG_NAME="DisplayWeave-macOS.dmg"
APKSIGNER="${ANDROID_SDK_ROOT:-${ANDROID_HOME:-$HOME/Library/Android/sdk}}/build-tools/36.1.0/apksigner"
KEYSTORE_PATH="${DISPLAYWEAVE_ANDROID_KEYSTORE:-$HOME/Library/Application Support/DisplayWeave/Signing/android-preview.jks}"
KEY_ALIAS="${DISPLAYWEAVE_ANDROID_KEY_ALIAS:-displayweave-preview}"
KEYCHAIN_SERVICE="app.displayweave.android-preview-signing"
# Keep the same Apple signing identity across releases. No certificate
# auto-selection, key export, or silent ad-hoc fallback is allowed.
signing_output="$(python3 "$ROOT_DIR/tools/mac_signing.py" xcode-settings)"
signing_options=()
while IFS= read -r option; do signing_options+=("$option"); done <<< "$signing_output"
if [[ -e "$OUT_DIR" ]]; then
  echo "Release output already exists; choose a new output directory." >&2
  exit 2
fi
if [[ ! -d "${DISPLAYWEAVE_MAC_BASELINE_APP:-}" ]]; then
  echo "Set DISPLAYWEAVE_MAC_BASELINE_APP to the previous published Mac app for upgrade identity verification." >&2
  exit 2
fi
STAGE_DIR="$(mktemp -d "${TMPDIR:-/tmp}/displayweave-release.XXXXXX")"

MAC_ARCHIVE_NAME="DisplayWeave-macOS.zip"
ANDROID_ARCHIVE_NAME="DisplayWeave-Android.apk"
IOS_ARCHIVE_NAME="DisplayWeave-iOS-unsigned-resigning-input.ipa"

cleanup() {
  unset password DISPLAYWEAVE_ANDROID_KEYSTORE DISPLAYWEAVE_ANDROID_STORE_PASSWORD
  unset DISPLAYWEAVE_ANDROID_KEY_ALIAS DISPLAYWEAVE_ANDROID_KEY_PASSWORD
  rm -rf "$STAGE_DIR"
}
trap cleanup EXIT

mkdir -p "$OUT_DIR"
cd "$ROOT_DIR"
./generate.sh

# This path preserves the pinned Apple identity and is not notarized. Developer
# ID notarization remains a separate credential-dependent workflow. Both use the
# normal entitlement set; Xcode signs embedded Sparkle with the same identity.
xcodebuild -quiet \
  -project OpenSidecar.xcodeproj \
  -scheme OpenSidecarMac \
  -configuration Release \
  -derivedDataPath "$MAC_DERIVED" \
  -clonedSourcePackagesDirPath "$MAC_DERIVED/SourcePackages" \
  MARKETING_VERSION="$VERSION_NAME" \
  CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
  ARCHS='arm64 x86_64' ONLY_ACTIVE_ARCH=NO \
  "${signing_options[@]}" \
  build

MAC_APP="$MAC_DERIVED/Build/Products/Release/DisplayWeave.app"
python3 "$ROOT_DIR/tools/mac_signing.py" verify "$MAC_APP"
comparison=(python3 "$ROOT_DIR/tools/mac_signing.py" compare "$MAC_APP"
            --baseline "$DISPLAYWEAVE_MAC_BASELINE_APP")
if [[ "${DISPLAYWEAVE_ALLOW_ADHOC_MIGRATION:-0}" == "1" ]]; then
  comparison+=(--allow-adhoc-migration)
fi
"${comparison[@]}"
ditto -c -k --sequesterRsrc --keepParent \
  "$MAC_APP" "$OUT_DIR/$MAC_ARCHIVE_NAME"
"$ROOT_DIR/tools/create-guided-dmg.sh" \
  "$MAC_APP" "$OUT_DIR/$MAC_DMG_NAME"

xcodebuild -quiet \
  -project OpenSidecar.xcodeproj \
  -scheme OpenSidecariOS \
  -configuration Release \
  -sdk iphoneos \
  -destination 'generic/platform=iOS' \
  -derivedDataPath "$IOS_DERIVED" \
  -clonedSourcePackagesDirPath "$IOS_DERIVED/SourcePackages" \
  MARKETING_VERSION="$VERSION_NAME" \
  CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  build

IOS_SOURCE_APP="$IOS_DERIVED/Build/Products/Release-iphoneos/OpenSidecariOS.app"
IOS_STAGED_APP="$STAGE_DIR/Payload/DisplayWeave.app"
mkdir -p "$STAGE_DIR/Payload"
cp -R "$IOS_SOURCE_APP" "$IOS_STAGED_APP"
xattr -cr "$IOS_STAGED_APP"
test ! -e "$IOS_STAGED_APP/_CodeSignature"
test "$(plutil -extract CFBundleIdentifier raw "$IOS_STAGED_APP/Info.plist")" \
  = "com.cyh.opendisplay.receiver"
IOS_EXECUTABLE="$(plutil -extract CFBundleExecutable raw "$IOS_STAGED_APP/Info.plist")"
lipo -info "$IOS_STAGED_APP/$IOS_EXECUTABLE"
rm -f "$OUT_DIR/$IOS_ARCHIVE_NAME"
(
  cd "$STAGE_DIR"
  COPYFILE_DISABLE=1 /usr/bin/zip -qry -X "$OUT_DIR/$IOS_ARCHIVE_NAME" Payload
)
archive_listing="$(unzip -Z1 "$OUT_DIR/$IOS_ARCHIVE_NAME")"
if [[ "$archive_listing" == *"__MACOSX/"* || "$archive_listing" == *"/._"* ]]; then
  echo "iOS resigning input contains forbidden AppleDouble metadata." >&2
  exit 4
fi

test -f "$KEYSTORE_PATH"
if [[ -z "${DISPLAYWEAVE_ANDROID_STORE_PASSWORD:-}" ]]; then
  password="$(security find-generic-password \
    -s "$KEYCHAIN_SERVICE" -a "$KEY_ALIAS" -w)"
  export DISPLAYWEAVE_ANDROID_STORE_PASSWORD="$password"
  export DISPLAYWEAVE_ANDROID_KEY_PASSWORD="$password"
fi
export DISPLAYWEAVE_ANDROID_KEYSTORE="$KEYSTORE_PATH"
export DISPLAYWEAVE_ANDROID_KEY_ALIAS="$KEY_ALIAS"
export DISPLAYWEAVE_VERSION_NAME="$VERSION_NAME"
export DISPLAYWEAVE_BUILD_NUMBER="$BUILD_NUMBER"

cd "$ROOT_DIR/AndroidReceiver"
./gradlew --no-daemon clean test assembleRelease

unset password DISPLAYWEAVE_ANDROID_KEYSTORE DISPLAYWEAVE_ANDROID_STORE_PASSWORD
unset DISPLAYWEAVE_ANDROID_KEY_ALIAS DISPLAYWEAVE_ANDROID_KEY_PASSWORD

if [[ ! -f "$ANDROID_APK" ]]; then
  echo "Android release APK is unsigned; refusing to package it." >&2
  echo "Set DISPLAYWEAVE_ANDROID_KEYSTORE, DISPLAYWEAVE_ANDROID_STORE_PASSWORD," >&2
  echo "DISPLAYWEAVE_ANDROID_KEY_ALIAS, and DISPLAYWEAVE_ANDROID_KEY_PASSWORD." >&2
  exit 2
fi

"$APKSIGNER" verify --verbose --print-certs "$ANDROID_APK"
cp "$ANDROID_APK" "$OUT_DIR/$ANDROID_ARCHIVE_NAME"

cd "$OUT_DIR"
shasum -a 256 \
  "$MAC_ARCHIVE_NAME" \
  "$MAC_DMG_NAME" \
  "$ANDROID_ARCHIVE_NAME" \
  "$IOS_ARCHIVE_NAME" > SHA256SUMS.txt

echo "DisplayWeave $VERSION_NAME artifacts:"
ls -lh "$OUT_DIR"

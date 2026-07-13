#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
OUT_DIR="${DISPLAYWEAVE_OUTPUT_DIR:-$ROOT_DIR/build/preview-0.1}"
MAC_DERIVED="$ROOT_DIR/build/preview-0.1-mac-derived"
IOS_DERIVED="$ROOT_DIR/build/preview-0.1-ios-derived"
ANDROID_APK="$ROOT_DIR/AndroidReceiver/app/build/outputs/apk/release/app-release.apk"
VERSION_NAME="${DISPLAYWEAVE_VERSION_NAME:-0.1.0}"
BUILD_NUMBER="${DISPLAYWEAVE_BUILD_NUMBER:-1}"
UPDATE_RELEASE="${DISPLAYWEAVE_UPDATE_RELEASE:-0}"
APKSIGNER="${ANDROID_SDK_ROOT:-${ANDROID_HOME:-$HOME/Library/Android/sdk}}/build-tools/36.1.0/apksigner"
KEYSTORE_PATH="${DISPLAYWEAVE_ANDROID_KEYSTORE:-$HOME/Library/Application Support/DisplayWeave/Signing/android-preview.jks}"
KEY_ALIAS="${DISPLAYWEAVE_ANDROID_KEY_ALIAS:-displayweave-preview}"
KEYCHAIN_SERVICE="app.displayweave.android-preview-signing"
STAGE_DIR="$(mktemp -d "${TMPDIR:-/tmp}/displayweave-preview-0.1.XXXXXX")"

if [[ "$UPDATE_RELEASE" == "1" ]]; then
  MAC_ARCHIVE_NAME="DisplayWeave-macOS.zip"
  ANDROID_ARCHIVE_NAME="DisplayWeave-Android.apk"
else
  MAC_ARCHIVE_NAME="DisplayWeave-Preview-0.1-macOS.zip"
  ANDROID_ARCHIVE_NAME="DisplayWeave-Preview-0.1-Android.apk"
fi

cleanup() {
  unset password DISPLAYWEAVE_ANDROID_KEYSTORE DISPLAYWEAVE_ANDROID_STORE_PASSWORD
  unset DISPLAYWEAVE_ANDROID_KEY_ALIAS DISPLAYWEAVE_ANDROID_KEY_PASSWORD
  rm -rf "$STAGE_DIR"
}
trap cleanup EXIT

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
  MARKETING_VERSION="$VERSION_NAME" \
  CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
  CODE_SIGN_ENTITLEMENTS=Mac/OpenSidecarMacAdHoc.entitlements \
  CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO \
  build

MAC_APP="$MAC_DERIVED/Build/Products/Release/DisplayWeave.app"
codesign --verify --deep --strict --verbose=2 "$MAC_APP"
ditto -c -k --sequesterRsrc --keepParent \
  "$MAC_APP" "$OUT_DIR/$MAC_ARCHIVE_NAME"

IOS_ARCHIVE_NAME="DisplayWeave-Preview-0.1-iOS-unsigned-resigning-input.ipa"
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
  "$ANDROID_ARCHIVE_NAME" \
  "$IOS_ARCHIVE_NAME" > SHA256SUMS.txt

echo "DisplayWeave Preview 0.1 artifacts:"
ls -lh "$OUT_DIR"

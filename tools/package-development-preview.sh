#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
OUT_DIR="$ROOT_DIR/build/preview"
MAC_DERIVED="$ROOT_DIR/build/preview-mac-derived"
IOS_DERIVED="$ROOT_DIR/build/preview-ios-derived"
STAGE_DIR="$(mktemp -d "${TMPDIR:-/tmp}/displayweave-preview.XXXXXX")"
trap 'rm -rf "$STAGE_DIR"' EXIT

mkdir -p "$OUT_DIR"

cd "$ROOT_DIR"
./generate.sh

xcodebuild -quiet \
  -project OpenSidecar.xcodeproj \
  -scheme OpenSidecarMac \
  -configuration Debug \
  -derivedDataPath "$MAC_DERIVED" \
  -clonedSourcePackagesDirPath "$MAC_DERIVED/SourcePackages" \
  build

xcodebuild -quiet \
  -project OpenSidecar.xcodeproj \
  -scheme OpenSidecariOS \
  -configuration Debug \
  -sdk iphonesimulator \
  -derivedDataPath "$IOS_DERIVED" \
  -clonedSourcePackagesDirPath "$IOS_DERIVED/SourcePackages" \
  build CODE_SIGNING_ALLOWED=NO

cd "$ROOT_DIR/AndroidReceiver"
./gradlew clean assembleDebug test

cd "$ROOT_DIR"
ditto -c -k --sequesterRsrc --keepParent \
  "$MAC_DERIVED/Build/Products/Debug/DisplayWeave.app" \
  "$OUT_DIR/DisplayWeave-macOS-development-preview.zip"

cp -R \
  "$IOS_DERIVED/Build/Products/Debug-iphonesimulator/OpenSidecariOS.app" \
  "$STAGE_DIR/DisplayWeave-iOS-Simulator.app"
ditto -c -k --sequesterRsrc --keepParent \
  "$STAGE_DIR/DisplayWeave-iOS-Simulator.app" \
  "$OUT_DIR/DisplayWeave-iOS-Simulator-development-preview.zip"

cp \
  "$ROOT_DIR/AndroidReceiver/app/build/outputs/apk/debug/app-debug.apk" \
  "$OUT_DIR/DisplayWeave-Android-debug.apk"

cd "$OUT_DIR"
shasum -a 256 \
  DisplayWeave-macOS-development-preview.zip \
  DisplayWeave-iOS-Simulator-development-preview.zip \
  DisplayWeave-Android-debug.apk > SHA256SUMS.txt

echo "Development preview artifacts:"
ls -lh "$OUT_DIR"

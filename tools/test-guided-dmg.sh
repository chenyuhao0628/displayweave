#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEMP="$(mktemp -d "${TMPDIR:-/tmp}/displayweave-dmg-test.XXXXXX")"
MOUNT="$TEMP/mount"
DEVICE=""

cleanup() {
  if [[ -n "$DEVICE" ]]; then
    hdiutil detach "$DEVICE" -quiet || true
  fi
  rm -rf "$TEMP"
}
trap cleanup EXIT

APP="$TEMP/DisplayWeave.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$MOUNT"
cp /usr/bin/true "$APP/Contents/MacOS/DisplayWeave"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>DisplayWeave</string>
<key>CFBundleIdentifier</key><string>app.displayweave.mac</string>
<key>CFBundleName</key><string>DisplayWeave</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>9.8.7</string>
<key>CFBundleVersion</key><string>987</string>
<key>SUFeedURL</key><string>https://chenyuhao0628.github.io/displayweave/appcast.xml</string>
<key>SUPublicEDKey</key><string>N9dMZV/F1ui58IsEmCv5jFVgDWiWv2yB/01KBlAHFjE=</string>
</dict></plist>
PLIST
chmod +x "$APP/Contents/MacOS/DisplayWeave"
codesign --force --deep --sign - "$APP"

DMG="$TEMP/DisplayWeave-macOS.dmg"
"$ROOT/tools/create-guided-dmg.sh" "$APP" "$DMG"
hdiutil verify "$DMG" >/dev/null
attach_output="$(hdiutil attach -readonly -nobrowse -mountpoint "$MOUNT" "$DMG")"
DEVICE="$(awk '$1 ~ /^\/dev\// { print $1; exit }' <<<"$attach_output")"

test -d "$MOUNT/DisplayWeave.app"
test -L "$MOUNT/Applications"
test "$(readlink "$MOUNT/Applications")" = /Applications
test -f "$MOUNT/安装与首次运行说明.rtf"
test -f "$MOUNT/.background/DisplayWeave.png"
test -f "$MOUNT/.DS_Store"
if ! strings "$MOUNT/.DS_Store" | grep -q 'backgroundImageAlias'; then
  echo "guided DMG background image alias is missing from Finder view options" >&2
  exit 1
fi
strings "$MOUNT/安装与首次运行说明.rtf" | grep -q 'Control'
strings "$MOUNT/安装与首次运行说明.rtf" | grep -q 'Open Anyway'
test "$(plutil -extract CFBundleIdentifier raw "$MOUNT/DisplayWeave.app/Contents/Info.plist")" = app.displayweave.mac
test "$(shasum -a 256 "$APP/Contents/MacOS/DisplayWeave" | awk '{print $1}')" = \
  "$(shasum -a 256 "$MOUNT/DisplayWeave.app/Contents/MacOS/DisplayWeave" | awk '{print $1}')"
codesign --verify --deep --strict --verbose=2 "$MOUNT/DisplayWeave.app"
echo "guided DMG contract PASS"

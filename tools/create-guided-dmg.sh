#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "usage: $0 DisplayWeave.app output.dmg" >&2
  exit 64
fi

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_INPUT="$1"
OUTPUT_INPUT="$2"
VOLUME_NAME="DisplayWeave Installer"

if [[ ! -d "$APP_INPUT/Contents" ]]; then
  echo "not an app bundle: $APP_INPUT" >&2
  exit 64
fi

APP="$(cd "$(dirname "$APP_INPUT")" && pwd)/$(basename "$APP_INPUT")"
mkdir -p "$(dirname "$OUTPUT_INPUT")"
OUTPUT="$(cd "$(dirname "$OUTPUT_INPUT")" && pwd)/$(basename "$OUTPUT_INPUT")"
TEMP="$(mktemp -d "${TMPDIR:-/tmp}/displayweave-guided-dmg.XXXXXX")"
STAGE="$TEMP/stage"
MOUNT=""
VERIFY_MOUNT="$TEMP/verify-mount"
RW_DMG="$TEMP/DisplayWeave-rw.dmg"
FINAL_DMG="$TEMP/DisplayWeave-final.dmg"
DEVICE=""

cleanup() {
  if [[ -n "$DEVICE" ]]; then
    hdiutil detach "$DEVICE" -quiet || true
  fi
  rm -rf "$TEMP"
}
trap cleanup EXIT

codesign --verify --deep --strict --verbose=2 "$APP"
bundle_id="$(plutil -extract CFBundleIdentifier raw "$APP/Contents/Info.plist")"
if [[ "$bundle_id" != "app.displayweave.mac" ]]; then
  echo "unexpected bundle identifier: $bundle_id" >&2
  exit 2
fi

mkdir -p "$STAGE/.background" "$VERIFY_MOUNT"
ditto "$APP" "$STAGE/DisplayWeave.app"
ln -s /Applications "$STAGE/Applications"
CLANG_MODULE_CACHE_PATH="$TEMP/clang-module-cache" \
SWIFT_MODULE_CACHE_PATH="$TEMP/swift-module-cache" \
  "$ROOT/tools/render-dmg-background.swift" \
  "$STAGE/.background/DisplayWeave.png"

cat > "$TEMP/instructions.txt" <<'TEXT'
DisplayWeave 安装与首次运行说明

1. 安装：把 DisplayWeave.app 拖入“Applications（应用程序）”，然后从
“应用程序”启动。请勿长期从 DMG 内运行。

2. 首次打开：可按住 Control 点按 DisplayWeave 并选择“打开”。若仍被 macOS
拦截，请前往“系统设置 → 隐私与安全性”，找到 DisplayWeave 后选择“仍要打开”。

3. 无需打开任何来源：请勿全局开启“任何来源”，也不要运行
spctl --master-disable；只对你从官方 Release 下载的 DisplayWeave 执行单次放行。

4. 运行权限：按应用提示授予“屏幕录制”“辅助功能”和“本地网络”权限。修改屏幕
录制或辅助功能权限后，请退出并重新启动 DisplayWeave。

5. 验证来源：本预览包采用 ad-hoc 签名且未经过 Apple 公证。请只从 DisplayWeave
官方 GitHub Release 下载，并使用 SHA256SUMS.txt 核对文件。

DMG 与 ZIP 中包含同一个支持 Sparkle 更新的 DisplayWeave.app；无论采用哪种安装
方式，放入“应用程序”后都可以接收后续更新。

Installation and first run

1. Install: Drag DisplayWeave.app to Applications, then launch it from
Applications. Do not keep running it from the DMG.

2. First open: Control-click DisplayWeave and choose Open. If macOS still
blocks it, go to System Settings → Privacy & Security and choose Open Anyway
for DisplayWeave.

3. Do not enable Anywhere globally: Do not run spctl --master-disable.
Override Gatekeeper only for the copy of DisplayWeave downloaded from the
official Release.

4. Permissions: Grant Screen Recording, Accessibility, and Local Network when
requested. Quit and relaunch DisplayWeave after changing Screen Recording or
Accessibility access.

5. Verify the download: This preview is ad-hoc signed and not Apple-notarized.
Download it only from the official DisplayWeave GitHub Release and verify it
against SHA256SUMS.txt.

The DMG and ZIP contain the same update-capable DisplayWeave.app. Either
installation receives later Sparkle updates after the app is placed in
Applications.
TEXT

ruby - "$TEMP/instructions.txt" \
  "$STAGE/安装与首次运行说明.rtf" <<'RUBY'
input, output = ARGV
body = File.read(input, encoding: "UTF-8").each_codepoint.map do |codepoint|
  case codepoint
  when 10
    "\\par\n"
  when 92, 123, 125
    "\\#{codepoint.chr}"
  when 32..126
    codepoint.chr
  else
    units = if codepoint <= 0xffff
      [codepoint]
    else
      scalar = codepoint - 0x10000
      [0xd800 + (scalar >> 10), 0xdc00 + (scalar & 0x3ff)]
    end
    units.map { |unit| "\\u#{unit > 32767 ? unit - 65536 : unit}?" }.join
  end
end.join
File.write(
  output,
  "{\\rtf1\\ansi\\deff0{\\fonttbl{\\f0\\fnil Helvetica;}}\\f0\\fs24\n#{body}\n}"
)
RUBY

hdiutil create \
  -srcfolder "$STAGE" \
  -fs HFS+ \
  -volname "$VOLUME_NAME" \
  -format UDRW \
  "$RW_DMG" >/dev/null

attach_output="$(hdiutil attach \
  -readwrite \
  -noverify \
  -noautoopen \
  "$RW_DMG")"
DEVICE="$(awk '$1 ~ /^\/dev\// { print $1; exit }' <<<"$attach_output")"
MOUNT="$(awk '
  $1 ~ /^\/dev\// && NF >= 3 {
    mount = $3
    for (i = 4; i <= NF; i++) mount = mount " " $i
  }
  END { print mount }
' <<<"$attach_output")"
if [[ -z "$DEVICE" || -z "$MOUNT" || ! -d "$MOUNT" ]]; then
  echo "unable to determine writable DMG device" >&2
  exit 3
fi

osascript <<OSA
tell application "Finder"
  tell disk "$VOLUME_NAME"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set bounds of container window to {120, 120, 880, 620}
    set arrangement of icon view options of container window to not arranged
    set icon size of icon view options of container window to 104
    set text size of icon view options of container window to 13
    set background picture of icon view options of container window to file ".background:DisplayWeave.png"
    set position of item "DisplayWeave.app" of container window to {190, 245}
    set position of item "Applications" of container window to {570, 245}
    set position of item "安装与首次运行说明.rtf" of container window to {380, 405}
    update without registering applications
    delay 2
    close
  end tell
end tell
OSA

sync
for _ in 1 2 3 4 5; do
  [[ -f "$MOUNT/.DS_Store" ]] && break
  sleep 1
done
if [[ ! -f "$MOUNT/.DS_Store" ]]; then
  echo "Finder did not persist the DMG layout" >&2
  exit 3
fi

hdiutil detach "$DEVICE" -quiet
DEVICE=""
hdiutil convert \
  "$RW_DMG" \
  -format UDZO \
  -imagekey zlib-level=9 \
  -o "$FINAL_DMG" >/dev/null
hdiutil verify "$FINAL_DMG" >/dev/null

attach_output="$(hdiutil attach \
  -readonly \
  -nobrowse \
  -mountpoint "$VERIFY_MOUNT" \
  "$FINAL_DMG")"
DEVICE="$(awk '$1 ~ /^\/dev\// { print $1; exit }' <<<"$attach_output")"
if [[ -z "$DEVICE" ]]; then
  echo "unable to determine verification DMG device" >&2
  exit 3
fi
test -d "$VERIFY_MOUNT/DisplayWeave.app"
test "$(readlink "$VERIFY_MOUNT/Applications")" = /Applications
test -f "$VERIFY_MOUNT/安装与首次运行说明.rtf"
test -f "$VERIFY_MOUNT/.background/DisplayWeave.png"
test -f "$VERIFY_MOUNT/.DS_Store"
codesign --verify --deep --strict --verbose=2 \
  "$VERIFY_MOUNT/DisplayWeave.app"
hdiutil detach "$DEVICE" -quiet
DEVICE=""

mv -f "$FINAL_DMG" "$OUTPUT"
echo "Created guided DMG: $OUTPUT"

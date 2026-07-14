# Guided macOS DMG Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Publish a guided `DisplayWeave-macOS.dmg` beside the existing Sparkle ZIP, with drag-to-Applications and safe first-run permission instructions, while proving both packages contain the same update-capable app build.

**Architecture:** A focused shell script stages the existing signed app, a checked-in Swift/AppKit renderer creates the bilingual background, and native `hdiutil`/Finder automation produces the read-only DMG. The existing release verifier mounts the DMG and compares its app identity, version, executable, code resources, Sparkle feed URL, and Sparkle public key with the ZIP app before accepting the release.

**Tech Stack:** Bash, Swift/AppKit, `hdiutil`, Finder AppleScript, `codesign`, `plutil`, `textutil`, GitHub Actions, Sparkle 2.

---

## File map

- Create `tools/render-dmg-background.swift`: render the deterministic bilingual 760×500 DMG background.
- Create `tools/create-guided-dmg.sh`: validate one signed app, stage guidance, apply Finder layout, and produce one verified UDZO image.
- Create `tools/test-guided-dmg.sh`: build an ad-hoc fixture app and verify the complete image contract.
- Modify `tools/package-preview-0.1.sh`: generate the DMG from the same `MAC_APP` used for the ZIP and hash both.
- Modify `tools/verify-update-release.sh`: verify DMG contents and prove ZIP/DMG app equivalence and Sparkle configuration.
- Modify `.github/workflows/release.yml`: hash and upload the DMG while leaving appcast generation on ZIP.
- Modify `tools/check-release-links.sh`: require the new workflow contract without rewriting historical v0.2.0-preview.2 asset records.
- Modify `README.md`, `README.zh-CN.md`, `docs/automatic-updates.md`, and `docs/automatic-updates.zh-CN.md`: document first-install DMG versus Sparkle ZIP and safe Gatekeeper handling.

### Task 1: Pin the guided DMG contract with a failing integration test

**Files:**
- Create: `tools/test-guided-dmg.sh`

- [ ] **Step 1: Add an executable shell integration test**

Create `tools/test-guided-dmg.sh` with this complete fixture and assertion flow:

```bash
#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEMP="$(mktemp -d "${TMPDIR:-/tmp}/displayweave-dmg-test.XXXXXX")"
MOUNT="$TEMP/mount"
DEVICE=""

cleanup() {
  if [[ -n "$DEVICE" ]]; then hdiutil detach "$DEVICE" -quiet || true; fi
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
DEVICE="$(awk 'NR == 1 { print $1 }' <<<"$attach_output")"

test -d "$MOUNT/DisplayWeave.app"
test -L "$MOUNT/Applications"
test "$(readlink "$MOUNT/Applications")" = /Applications
test -f "$MOUNT/安装与首次运行说明.rtf"
test -f "$MOUNT/.background/DisplayWeave.png"
test -f "$MOUNT/.DS_Store"
strings "$MOUNT/安装与首次运行说明.rtf" | grep -q 'Control'
strings "$MOUNT/安装与首次运行说明.rtf" | grep -q 'Open Anyway'
test "$(plutil -extract CFBundleIdentifier raw "$MOUNT/DisplayWeave.app/Contents/Info.plist")" = app.displayweave.mac
test "$(shasum -a 256 "$APP/Contents/MacOS/DisplayWeave" | awk '{print $1}')" = \
  "$(shasum -a 256 "$MOUNT/DisplayWeave.app/Contents/MacOS/DisplayWeave" | awk '{print $1}')"
codesign --verify --deep --strict --verbose=2 "$MOUNT/DisplayWeave.app"
echo "guided DMG contract PASS"
```

Run `chmod +x tools/test-guided-dmg.sh`.

- [ ] **Step 2: Run the test and confirm the missing implementation failure**

Run:

```bash
./tools/test-guided-dmg.sh
```

Expected: FAIL with `tools/create-guided-dmg.sh: No such file or directory`.

- [ ] **Step 3: Commit the red test**

```bash
git add tools/test-guided-dmg.sh
git commit -m "test: define guided DMG contract"
```

### Task 2: Render the bilingual DMG background

**Files:**
- Create: `tools/render-dmg-background.swift`

- [ ] **Step 1: Add the complete deterministic AppKit renderer**

Create a Swift command-line source that requires exactly one output path, creates a 760×500 bitmap, paints an opaque adaptive-neutral background, draws the DisplayWeave title, a center arrow, bilingual drag text, and the short first-run line. Use explicit sRGB colors and system fonts so it does not depend on checked-in binary artwork. Its final write path must be:

```swift
guard CommandLine.arguments.count == 2 else {
    fputs("usage: render-dmg-background.swift OUTPUT.png\n", stderr)
    exit(64)
}

let size = NSSize(width: 760, height: 500)
let image = NSImage(size: size)
image.lockFocus()
NSColor(calibratedRed: 0.055, green: 0.075, blue: 0.12, alpha: 1).setFill()
NSBezierPath(rect: NSRect(origin: .zero, size: size)).fill()

func draw(_ text: String, at point: NSPoint, width: CGFloat,
          font: NSFont, color: NSColor = .white,
          alignment: NSTextAlignment = .center) {
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = alignment
    text.draw(in: NSRect(x: point.x, y: point.y, width: width, height: 80),
              withAttributes: [.font: font, .foregroundColor: color,
                               .paragraphStyle: paragraph])
}

draw("DisplayWeave", at: NSPoint(x: 80, y: 425), width: 600,
     font: .systemFont(ofSize: 30, weight: .semibold))
draw("拖入“应用程序”完成安装", at: NSPoint(x: 80, y: 350), width: 600,
     font: .systemFont(ofSize: 21, weight: .medium))
draw("Drag DisplayWeave to Applications", at: NSPoint(x: 80, y: 320), width: 600,
     font: .systemFont(ofSize: 15), color: NSColor(white: 0.78, alpha: 1))
draw("➜", at: NSPoint(x: 300, y: 205), width: 160,
     font: .systemFont(ofSize: 64, weight: .light),
     color: NSColor(calibratedRed: 0.35, green: 0.78, blue: 1, alpha: 1))
draw("首次运行若被拦截：系统设置 → 隐私与安全性 → 仍要打开",
     at: NSPoint(x: 60, y: 55), width: 640,
     font: .systemFont(ofSize: 14, weight: .medium))
draw("First run: System Settings → Privacy & Security → Open Anyway",
     at: NSPoint(x: 60, y: 28), width: 640,
     font: .systemFont(ofSize: 12), color: NSColor(white: 0.72, alpha: 1))
image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiff),
      let png = bitmap.representation(using: .png, properties: [:]) else {
    fputs("unable to encode background PNG\n", stderr)
    exit(2)
}
try png.write(to: URL(fileURLWithPath: CommandLine.arguments[1]), options: .atomic)
```

Include `#!/usr/bin/env swift`, `import AppKit`, and `import Foundation`, then make the file executable.

- [ ] **Step 2: Compile and render a smoke-test image**

Run:

```bash
swiftc -typecheck tools/render-dmg-background.swift
tools/render-dmg-background.swift /tmp/DisplayWeave-dmg-background.png
sips -g pixelWidth -g pixelHeight /tmp/DisplayWeave-dmg-background.png
```

Expected: typecheck succeeds and `sips` reports `pixelWidth: 760`, `pixelHeight: 500`.

- [ ] **Step 3: Commit the renderer**

```bash
git add tools/render-dmg-background.swift
git commit -m "feat: render guided DMG background"
```

### Task 3: Implement native guided DMG creation

**Files:**
- Create: `tools/create-guided-dmg.sh`
- Test: `tools/test-guided-dmg.sh`

- [ ] **Step 1: Add input validation, staging, and bilingual guidance**

Implement `tools/create-guided-dmg.sh` with `set -euo pipefail`, exactly two positional arguments, absolute input/output resolution, and these invariants before image creation:

```bash
[[ -d "$APP/Contents" ]] || { echo "not an app bundle: $APP" >&2; exit 64; }
codesign --verify --deep --strict --verbose=2 "$APP"
[[ "$(plutil -extract CFBundleIdentifier raw "$APP/Contents/Info.plist")" == \
  "app.displayweave.mac" ]] || { echo "unexpected bundle identifier" >&2; exit 2; }

mkdir -p "$STAGE/.background"
ditto "$APP" "$STAGE/DisplayWeave.app"
ln -s /Applications "$STAGE/Applications"
"$ROOT/tools/render-dmg-background.swift" "$STAGE/.background/DisplayWeave.png"
```

Generate UTF-8 HTML in the temporary directory and convert it with
`textutil -convert rtf -output "$STAGE/安装与首次运行说明.rtf"`. The document must contain the five approved instructions: drag to Applications; Control-click/Open and Privacy & Security/Open Anyway; never enable Anywhere globally; grant Screen Recording, Accessibility, and Local Network then relaunch; verify the official GitHub Release checksum. Include the same content in English after the Chinese section.

- [ ] **Step 2: Add writable image creation and Finder layout**

Use a 32 MB HFS+ UDRW image, mount it at a temporary path, and use Finder AppleScript with these stable layout values:

```applescript
tell application "Finder"
  tell disk "DisplayWeave Installer"
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
```

After `sync`, require `.DS_Store`, detach the device, convert with `hdiutil convert -format UDZO -imagekey zlib-level=9`, and atomically move the converted image to the requested output only after `hdiutil verify` succeeds. A cleanup trap must detach any active device and delete all temporary files and partial output.

- [ ] **Step 3: Run the contract test to green**

```bash
chmod +x tools/create-guided-dmg.sh
./tools/test-guided-dmg.sh
```

Expected: `guided DMG contract PASS` and no mounted `DisplayWeave Installer` volume remains.

- [ ] **Step 4: Run negative checks**

```bash
if tools/create-guided-dmg.sh /tmp/missing.app /tmp/should-not-exist.dmg; then exit 1; fi
test ! -e /tmp/should-not-exist.dmg
```

Expected: the command fails with `not an app bundle`, and no partial DMG exists.

- [ ] **Step 5: Commit the generator**

```bash
git add tools/create-guided-dmg.sh
git commit -m "feat: create guided macOS DMG"
```

### Task 4: Add DMG packaging and ZIP/DMG equivalence verification

**Files:**
- Modify: `tools/package-preview-0.1.sh`
- Modify: `tools/verify-update-release.sh`

- [ ] **Step 1: Extend the release verifier contract first**

Add `mac_dmg="$directory/DisplayWeave-macOS.dmg"` to the required artifacts. Before Android verification, mount the DMG read-only under the existing temporary directory, trap detachment as well as directory cleanup, and assert:

```bash
hdiutil verify "$mac_dmg" >/dev/null
DMG_MOUNT="$temporary/dmg"
mkdir -p "$DMG_MOUNT"
attach_output="$(hdiutil attach -readonly -nobrowse -mountpoint "$DMG_MOUNT" "$mac_dmg")"
DMG_DEVICE="$(awk 'NR == 1 { print $1 }' <<<"$attach_output")"
test -d "$DMG_MOUNT/DisplayWeave.app"
test "$(readlink "$DMG_MOUNT/Applications")" = /Applications
test -f "$DMG_MOUNT/安装与首次运行说明.rtf"
test -f "$DMG_MOUNT/.background/DisplayWeave.png"
test -f "$DMG_MOUNT/.DS_Store"
codesign --verify --deep --strict --verbose=2 "$DMG_MOUNT/DisplayWeave.app"
```

Resolve the ZIP app root from `mac_plist`, then compare the following values with the DMG app and fail with a specific message for each mismatch:

- `CFBundleIdentifier`
- `CFBundleShortVersionString`
- `CFBundleVersion`
- `SUFeedURL`
- `SUPublicEDKey`
- SHA-256 of `Contents/MacOS/DisplayWeave`
- SHA-256 of `Contents/_CodeSignature/CodeResources`

Also fail if appcast contains `DisplayWeave-macOS.dmg`; it must continue to contain `DisplayWeave-macOS.zip` and an EdDSA signature.

- [ ] **Step 2: Run verifier syntax and expected-red checks**

```bash
bash -n tools/verify-update-release.sh
DISPLAYWEAVE_VERSION_NAME=0.0.0 DISPLAYWEAVE_BUILD_NUMBER=1 \
  ./tools/verify-update-release.sh /tmp/nonexistent-release
```

Expected: syntax passes; verifier fails with `Missing release artifact` mentioning the missing DMG or ZIP.

- [ ] **Step 3: Generate the DMG beside the ZIP from one `MAC_APP`**

In `tools/package-preview-0.1.sh`, define `MAC_DMG_NAME="DisplayWeave-macOS.dmg"`. Immediately after the existing ZIP creation, call:

```bash
"$ROOT_DIR/tools/create-guided-dmg.sh" \
  "$MAC_APP" "$OUT_DIR/$MAC_DMG_NAME"
```

Add `"$MAC_DMG_NAME"` to the `shasum -a 256` input list. Do not change `MAC_ARCHIVE_NAME`; Sparkle continues to use the ZIP.

- [ ] **Step 4: Run static and focused packaging checks**

```bash
bash -n tools/package-preview-0.1.sh tools/verify-update-release.sh
rg -n 'DisplayWeave-macOS\.(zip|dmg)' tools/package-preview-0.1.sh tools/verify-update-release.sh
./tools/test-guided-dmg.sh
```

Expected: both filenames appear with distinct roles and the integration test passes.

- [ ] **Step 5: Commit packaging and verification**

```bash
git add tools/package-preview-0.1.sh tools/verify-update-release.sh
git commit -m "feat: package and verify macOS DMG"
```

### Task 5: Publish the DMG without changing Sparkle delivery

**Files:**
- Modify: `.github/workflows/release.yml`
- Modify: `tools/check-release-links.sh`

- [ ] **Step 1: Make the workflow contract test fail for the missing DMG**

Add `DisplayWeave-macOS.dmg` to `workflow_contract` in `tools/check-release-links.sh`, but do not add it to the historical `assets` list for v0.2.0-preview.2.

Run:

```bash
./tools/check-release-links.sh
```

Expected: FAIL with `release workflow is missing update contract marker: DisplayWeave-macOS.dmg`.

- [ ] **Step 2: Add DMG hashing and upload to the workflow**

In `.github/workflows/release.yml`:

- Add `DisplayWeave-macOS.dmg` to the final `shasum -a 256` command.
- Add `"$DISPLAYWEAVE_OUTPUT_DIR/DisplayWeave-macOS.dmg"` to `gh release upload`.
- Keep `generate_appcast` pointed at the output directory and keep the explicit ZIP appcast verification in `tools/verify-update-release.sh`.

- [ ] **Step 3: Run workflow contract checks**

```bash
./tools/check-release-links.sh
rg -n 'DisplayWeave-macOS.dmg|DisplayWeave-macOS.zip' .github/workflows/release.yml
```

Expected: release-link check passes; DMG is hashed/uploaded, while ZIP remains present for appcast delivery.

- [ ] **Step 4: Commit CI integration**

```bash
git add .github/workflows/release.yml tools/check-release-links.sh
git commit -m "ci: publish guided macOS DMG"
```

### Task 6: Document first installation and ongoing updates bilingually

**Files:**
- Modify: `README.md`
- Modify: `README.zh-CN.md`
- Modify: `docs/automatic-updates.md`
- Modify: `docs/automatic-updates.zh-CN.md`

- [ ] **Step 1: Update README download and migration guidance**

In both README files, keep the historical v0.2.0-preview.2 table accurate. Add a clearly marked “next release packaging” paragraph that says:

- DMG is the recommended first-install artifact.
- Drag the app into Applications before launching.
- ZIP remains the Sparkle update payload and an alternate manual install.
- Both contain the same app build and both installations receive later Sparkle updates.
- For the current ad-hoc/notarization state, use per-app Control-click/Open or Privacy & Security/Open Anyway; never enable Anywhere globally.

- [ ] **Step 2: Update automatic-update architecture and user steps**

In both automatic update documents, list:

```text
Mac first-install artifact: DisplayWeave-macOS.dmg
Mac update artifact: DisplayWeave-macOS.zip
```

Change the Mac migration step to recommend DMG drag-to-Applications, state that ZIP installation is equivalent after the app reaches `/Applications`, and explicitly explain that Sparkle capability lives inside `DisplayWeave.app` rather than in its installation container.

- [ ] **Step 3: Run bilingual and terminology checks**

```bash
./tools/check-bilingual-docs.sh
./tools/check-release-links.sh
rg -n '任何来源|仍要打开|Open Anyway|DisplayWeave-macOS.dmg|DisplayWeave-macOS.zip' \
  README.md README.zh-CN.md docs/automatic-updates.md docs/automatic-updates.zh-CN.md
```

Expected: both repository checks pass; each language documents DMG first install, ZIP updates, and per-app Gatekeeper override.

- [ ] **Step 4: Commit documentation**

```bash
git add README.md README.zh-CN.md docs/automatic-updates.md docs/automatic-updates.zh-CN.md
git commit -m "docs: explain guided DMG installation"
```

### Task 7: Build and verify a real distributable image

**Files:**
- Verify only; no planned source edits.

- [ ] **Step 1: Run all fast checks**

```bash
bash -n tools/create-guided-dmg.sh tools/test-guided-dmg.sh \
  tools/package-preview-0.1.sh tools/verify-update-release.sh
swiftc -typecheck tools/render-dmg-background.swift
./tools/test-guided-dmg.sh
./tools/check-bilingual-docs.sh
./tools/check-release-links.sh
git diff --check
```

Expected: every command exits 0.

- [ ] **Step 2: Generate a DMG from the existing Release app or rebuild it**

If `build/preview-0.1-mac-derived/Build/Products/Release/DisplayWeave.app` exists, run:

```bash
mkdir -p build/guided-dmg-verification
./tools/create-guided-dmg.sh \
  build/preview-0.1-mac-derived/Build/Products/Release/DisplayWeave.app \
  build/guided-dmg-verification/DisplayWeave-macOS.dmg
```

Otherwise regenerate the Xcode project and build only the macOS Release target with the same ad-hoc entitlement arguments used by `tools/package-preview-0.1.sh`, then run the command above.

Expected: `DisplayWeave-macOS.dmg` exists and `hdiutil verify` succeeds.

- [ ] **Step 3: Inspect the real image read-only**

```bash
hdiutil verify build/guided-dmg-verification/DisplayWeave-macOS.dmg
./tools/test-guided-dmg.sh
```

Then open the DMG once and confirm: 760×500 Finder window, app left, Applications right, arrow centered, bilingual drag text visible, permission line readable, and the RTF opens with both language sections. Confirm dragging produces `/Applications/DisplayWeave.app` and launching it exposes the same Sparkle feed URL as the ZIP build.

- [ ] **Step 4: Review the final repository state**

```bash
git status --short
git log --oneline -8
git diff HEAD~6 --check
```

Expected: only intentional commits/files are present, with no whitespace errors or untracked release artifacts.

- [ ] **Step 5: Record verification evidence**

If verification required no source corrections, no commit is needed. If a concrete defect was found, add a focused failing assertion first, make the minimum repair, rerun all Task 7 checks, and commit the test plus repair with a message naming the corrected defect.

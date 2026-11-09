[English](brand-assets.md) | [简体中文](brand-assets.zh-CN.md)

# DisplayWeave brand assets

Updated 2026-11-09. Source has reproducible exports, Mac legacy rounded-square tiles and Android adaptive packaging. The existing blue/teal device mark is preserved. Its opaque raster is still a temporary derivative, **not a final editable or transparent master**. The local p8 artifact predates this export workflow; v0.3.0 previews include the reproducible exports.

## Sources and exports

| Asset | Source / rule |
| --- | --- |
| Mark | `public/icon.png`, 1024×1024 RGB; SHA-256 recorded in `tools/brand-assets.json` |
| Full wordmark | `public/logo.png`, 1254×1254 opaque; retained unchanged |
| Social card | `public/og.png`, 1200×630 opaque; retained unchanged |
| Mac icon | 16–1024 px RGBA legacy tiles from `Mac/Assets.xcassets/AppIcon.appiconset/Contents.json`, with transparent outer padding |
| iOS icon | Sizes from `iOS/Assets.xcassets/AppIcon.appiconset/Contents.json`, including 1024 px marketing image |
| In-app mark | iOS `AppLogo` and Android `drawable/app_logo.png`, 512 px |
| Web small mark | `public/icon-256.png`, 256 px |
| Android legacy | `mipmap-mdpi` through `mipmap-xxxhdpi`, 48/72/96/144/192 px |
| Android adaptive | `mipmap-anydpi-v26/ic_launcher.xml`, white background plus a 432 px RGBA foreground canvas |

The iOS 1024px export remains a byte-identical copy of the source. Other exports use pinned Pillow 12.3.0, Lanczos resampling and explicit PNG compression. Compressed PNG bytes can differ between zlib builds; verification compares dimensions, color mode and decoded pixels. The in-app and legacy resources are regenerated from that same source. The existing wordmark and social card are not reconstructed from the mark.

Mac app icons are a platform-specific derivative, not a replacement master: the complete opaque artwork is scaled into an 824px white tile inside a 1024px canvas, with 100px outer inset and a fifth-order superellipse outline. The colored mark remains inside the opaque portion. Smaller Mac icons use Lanczos for color and area filtering for alpha to avoid faint edge pixels consuming the 16/32px padding. The existing bundle-local `.icns` loading safeguard is retained. This legacy ICNS treatment is separate from modern [Icon Composer layers](https://developer.apple.com/design/human-interface-guidelines/app-icons), which should remain unmasked; iOS, Android and web exports keep their existing pixels.

```bash
python3 -m venv build/brand-venv
build/brand-venv/bin/pip install -r tools/brand-requirements.txt
build/brand-venv/bin/python tools/export-brand-assets.py --check
# After reviewing intended changes:
build/brand-venv/bin/python tools/export-brand-assets.py --write --preview build/brand-masks.png
```

`--check` detects missing outputs or changed decoded pixels (XML is byte-exact), validates Mac RGBA mode, transparent corners, opaque centers, inset bounds and the full-resolution colored-mark boundary, and verifies Android manifest selection and colored-mark safe bounds. It refuses a changed source checksum; a replacement master requires explicit review and a new checksum in the specification. No logo-background extraction or generated brand artwork is involved. The existing `--preview` contact sheet covers Android adaptive masks; Mac acceptance uses the packaged app in the Dock and Command-Tab switcher.

## Safe area, palette and usage

Android's adaptive layers use a 108dp canvas. The existing opaque icon is centered at 76dp, with a matching white background. All colored pixels fit inside the central 66dp-diameter safe circle. Transparency exists only outside the inset raster; it is **not** an extracted transparent logo. The XML is versioned for API 26+, and density PNGs remain available. No fabricated monochrome/themed mask is supplied: that requires a separately approved master.

Working palette: navy `#103A60`, teal `#00A5AF`, cyan `#00A9DE`, white `#FFFFFF`. These are practical companion colors, not exact replacements for the gradients in the artwork. UI status colors follow [the UI standard](ui-guidelines.md) and always have text labels.

Use the mark without a wordmark for icons. Keep at least one stroke width of clear space; never crop, stretch, recolor, add shadows or place the current opaque raster directly on a supposedly transparent surface. The Mac derivative changes only its outer tile and padding; the shared master and other platform backgrounds remain opaque and unchanged. For dark surfaces, use an explicit white tile with adequate surrounding contrast until an approved dark master exists. Do not call this a dark-logo variant. Use the mark at 32px or larger in ordinary content; the required 16px Mac icon is a platform fallback, not proof of small-size optical polish. Keep wordmark text comfortably readable rather than scaling the full square logo into a favicon.

## Evidence and external requirements

The exporter reproduces 36 assets and validates Mac transparency/padding and Android safe bounds. The former opaque Mac assets fail the new Mac checks; all seven regenerated Mac sizes pass. The shared masters and all 29 non-Mac exports were verified byte-identical. A signed arm64/x86_64 preview built from the actual Mac target retained the RGBA tile in its packaged `.icns`; the rounded icon was observed in the real Dock and Command-Tab switcher. Earlier Android assembly/Lint and Apple packaging records retain their original scope. This does not establish older-macOS or OEM-launcher acceptance.

The Mac-only corner shape and padding were accepted by the requesting owner on 2026-11-09. This does not replace or approve a new shared artwork master.

Still externally pending: approved editable SVG/PDF, transparent high-resolution master, dark/reversed and monochrome masters, final small-size optical corrections, and licensed real-device promotional screenshots. Original `newicon.svg` / `newnewicon.png` are absent. Do not invent approval or replace the existing identity. Once supplied, export all platform sets and inspect real launchers, Dock, Settings, onboarding and notification surfaces. Compatibility bundle IDs, target names and discovery identities stay unchanged.

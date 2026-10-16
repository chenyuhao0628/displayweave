[English](release-notes-v0.3.0-preview.3.md) | [简体中文](release-notes-v0.3.0-preview.3.zh-CN.md)

# DisplayWeave v0.3.0-preview.3

Release date: 2026-10-17 (Asia/Shanghai). Mac build / Android version code: **18**. Native/signing baseline: `92b5834`, which merges PR #16. This release carries the preview.2 UI and OpenDisplay compatibility forward and fixes the Mac build/signing path.

## Changes

- Mac preview builds use one pinned Apple Development identity. Run and packaging stop when the identity is unavailable or changes; they never silently fall back to ad-hoc signing.
- Upgrade packaging compares the actual designated requirements, team, bundle identity and architectures against the previous published app. Debug retains its separate bundle ID. Hardened runtime, normal empty Release entitlements and signed Sparkle are verified.
- Updated English/Chinese installation, update, signing and release guides, root documentation and website. Corrected stale current-version/signing claims and retired mirror instructions. See the [documentation audit](documentation-audit-2026-10-17.md).
- Existing preferences, pairing records, Bonjour service, wire framing, Sparkle key and Android signing certificate remain unchanged.

## Upgrade and compatibility

The first upgrade from preview.2 or another ad-hoc Mac release may require Screen Recording, Accessibility and Local Network authorization again. Once using the fixed identity, subsequent builds preserve that code identity. This does not override a user's denial, changed macOS policies or a deliberate future signer migration.

The new **build 18** was installed over local signed build **17.1** at `/Applications/DisplayWeave.app`: it launched successfully and Screen Recording/Accessibility remained allowed without reauthorization. The same three historic Local Network entries stayed enabled; no old-app backup was retained. Earlier signed build 17 → 17.1 also passed. No real receiver-traffic claim is inferred from the network toggles. See [permission continuity](mac-permissions.md).

OpenDisplay and DisplayWeave connection choices remain available on the main screen. A sending Mac selects **Both clients** for old and new receivers; a receiver selects **OpenDisplay compatibility** for an old sender. Legacy mode is unencrypted and requires no invitation; encrypted DisplayWeave pairing stays separate. See [compatibility coverage](opendisplay-compatibility.md). Per-device Native/1080p/1440p/4K extension resolution is retained; changing it rebuilds that device's session. Mirror mode follows the source display. See [desktop resolution](desktop-resolution.md).

## Verification

- Signing source CI `38932980548`: web/docs, Android and Mac/Swift all passed, including 52 Swift suites, Android tests/Lint, universal Mac Debug and iOS Simulator builds. Release-documentation CI is recorded separately in the publication PR.
- Signing regressions: 20 offline tests and the existing 12 Apple-distribution checks passed. A real two-binary test retained the production Keychain transport identity and trusted peer, then deleted only its test namespace.
- Build 18 packaging: universal Apple-signed Mac Release, guided DMG/ZIP consistency and nested signatures, unsigned arm64 iOS Release, Android tests and Release with the original v2 certificate passed.
- Independently verified the ZIP Ed25519 signature, appcast version/size/URL, Android feed/hash/package/certificate and unsigned iOS version/identity. The checksums cover every other release asset.
- Local overwrite acceptance is recorded above. Prior preview.2 TLS/Keystore/synthetic-video and broader UI observations remain historical evidence; they were not rerun as physical acceptance for this signing-only release.

No independent online display was established, so interactive capture and virtual-display tests were skipped. Two-device LAN/USB performance, Intel runtime, all historical OpenDisplay binaries, Pencil hardware and endurance remain pending. Apple Development signing is not Developer ID notarization; this release is intentionally unnotarized. iOS remains a re-signing input requiring the user's valid identity.

## Downloads

[GitHub Release](https://github.com/chenyuhao0628/displayweave/releases/tag/v0.3.0-preview.3). Eight files: four binaries, two feeds, `DisplayWeave-v0.3.0-preview.3-source.tar.gz` and `SHA256SUMS.txt`. The source archive contains tracked source at the release tag, GPL-3.0, attribution and build scripts. Its hash is in the checksum manifest. Binaries/source use GitHub Releases only; live update metadata uses GitHub Pages. Previous assets remain unchanged.

| Asset | SHA-256 |
| --- | --- |
| `DisplayWeave-macOS.zip` | `b3a0a5e7d7dea6e9e487bd7e1f6b89e7bd3f3ddd597febbd99d7bf5276f41bd7` |
| `DisplayWeave-macOS.dmg` | `a29756e94f48f7eeab5968ed9c03e5aebaf0b74e743d69200748195dc6431518` |
| `DisplayWeave-Android.apk` | `370e1ba6b40cbeb9a66a3cfca280d0c5f9ab710d7b3d4a9468c4238c78646bf8` |
| `DisplayWeave-Preview-0.1-iOS-unsigned-resigning-input.ipa` | `83328fc764068b365b6726439c9a9f10dd22502a4244d74cbf7c78d5e862a29c` |
| `appcast.xml` | `42ceef4bb11625b042b4e1b08d92176ad2397f923d6a1b9f6dc9dc2584e15979` |
| `android-update.json` | `8f8dfb74f067240aa151908a0730b7bc822655d2b84d33ddff4ef4d3a61efd95` |

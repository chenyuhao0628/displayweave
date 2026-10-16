[English](release-notes-v0.2.1-p8.md) | [简体中文](release-notes-v0.2.1-p8.zh-CN.md)

# DisplayWeave `v0.2.1-p8` release notes

Version `0.2.1-p8`, Mac build / Android version code `15`, built locally on 2026-10-16. This release uses the reviewed p7 native feature source. Hosted Actions is unavailable, so publication uses local builds while preserving immutable p7 files and tag.

## Contents

Includes p7's exclusive Mac roles for one-way extend/mirror, hardware HEVC with H.264 fallback, interface-pinned direct-link candidates, negotiated Pencil pressure/tilt/hover, four-surface UI and session lifecycle hardening. See [p7 notes](release-notes-v0.2.1-p7.md) and the [feature guide](hevc-wired-pencil.md). p8 adds no native feature or fixed-resolution mode picker and changes no signing keys, application IDs, feed URLs or wire protocol.

Adds a reproducible [local publication procedure](local-release.md), preserved historical Cloudflare downloads, a backup site and corresponding source archive. Source is the tracked tree at the release tag, including GPL-3.0, upstream notices and build scripts.

## Automated verification and hardware boundaries

Local checks cover 37 Swift suites, Mac arm64/x86_64 Debug and Release, iOS Simulator Debug and unsigned arm64 Release, six Android self-test groups with Debug/signed Release, production website build, bilingual docs and release links. Build tools are Xcode 26.6 (17F113), OpenJDK 21.0.10 and pnpm 10.33.0.

`verify-update-release.sh` checks package versions, DMG/ZIP consistency, deep code signatures, the pinned Android certificate and hashes. CryptoKit independently verifies the Sparkle ZIP Ed25519 signature; Mac universal architectures and unsigned iOS identity/version are also checked. Hosted Actions is unavailable; no successful hosted CI is claimed for this release.

Two-Mac physical routing/performance, real Pencil pressure/tilt/hover/palm rejection, new UIKit gesture runtime, Intel runtime and 30-minute/2-hour endurance acceptance remain pending. The host had no verified independent online display, so virtual-display interaction was skipped. Automated checks do not establish on-screen performance.

## Downloads and updates

[Cloudflare download page](https://downloads.urlget.cyou/displayweave/) · [GitHub Release](https://github.com/chenyuhao0628/displayweave/releases/tag/v0.2.1-p8)

Eight files comprise the Mac DMG/Sparkle ZIP, Android APK, unsigned iOS re-signing input, `appcast.xml`, `android-update.json`, `DisplayWeave-v0.2.1-p8-source.tar.gz` and `SHA256SUMS.txt`. The source archive's SHA-256 is in the checksum manifest, which covers the other seven files.

Mac remains ad-hoc signed and not notarized; Android retains the package/certificate for in-place installation; iOS requires personal valid signing before installation. On 2026-10-16 authenticated GitHub management worked while public GitHub/Pages returned 404. Download manually from the mirror; Mac and Android still depend on original GitHub Pages metadata, so in-app updates cannot be guaranteed until those URLs recover. Feed copies on the backup site do not redirect clients.

## Artifact integrity

| Asset | SHA-256 |
| --- | --- |
| `DisplayWeave-macOS.zip` | `a83e6a0a0455bfe7f0c0a5b5cb70f4a1acdbc18b1f8f00c3e76f9eea419ac67c` |
| `DisplayWeave-macOS.dmg` | `f3c043d53cce3b459ce36f62ea640e70dfce9a3c9165cf2ec0326ee9d6b4579a` |
| `DisplayWeave-Android.apk` | `3f909af1bd0e6da09a72048b124d061aadd8284c2dad7beb0b8a3e7f568a098e` |
| `DisplayWeave-Preview-0.1-iOS-unsigned-resigning-input.ipa` | `8e423d4c6baf60d3b92c990f1d465473c223bce539baf3456abf59799f079bd1` |
| `appcast.xml` | `a16c4277d46e6f30185c629a060f356f341bb76dc5adb268cc1907ed4a662d47` |
| `android-update.json` | `b032f7cc19c963b5559306c3459e402fb5b87466f6e48d9b98044e68ea012ba2` |

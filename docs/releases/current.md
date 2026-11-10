[English](current.md) | [简体中文](current.zh-CN.md)

# DisplayWeave `v0.3.5` Stable Release Distribution

[GitHub Release](https://github.com/chenyuhao0628/displayweave/releases/tag/v0.3.5)

2026-11-10: build 24 hardens Android legacy V1 decoder recovery and asynchronous codec teardown, iOS Metal drawable/generation synchronization and rotated video admission, Mac receiver decoded-frame window gating, ADB/usbmux pipe and handshake bounds, and bilingual documentation. Requested or negotiated FPS is not measured physical refresh. See the [release notes](v0.3.5.md).

| Platform/feed | Asset | SHA-256 or trust boundary |
| --- | --- | --- |
| macOS first install | `DisplayWeave-macOS.dmg` | `ddcbe28b170d2efa9f160ad1d376986cbf137f0a5af7bcba9352266db2a7ec70`; pinned Apple Development signature, not notarized |
| macOS update | `DisplayWeave-macOS.zip` | `eb88bf026dba990b0f1d3bc89dfcd7963884be79f6409b33206d43b8675aa6bc`; EdDSA-authenticated Sparkle payload |
| Android | `DisplayWeave-Android.apk` | `25387fafb821321797a3d6a4ef79101ce89225b613edb63c9e65f642912e1db6`; v2 signed with the pinned project key |
| iOS/iPadOS | `DisplayWeave-iOS-unsigned-resigning-input.ipa` | `b79c1bbbe23c8a07b57df9be52d808ac68aee9471edd716251c81681253560b1`; unsigned arm64 re-signing input |
| Mac update feed | `appcast.xml` | [Configured Sparkle feed](https://chenyuhao0628.github.io/displayweave/appcast.xml) |
| Android update feed | `android-update.json` | [Configured metadata feed](https://chenyuhao0628.github.io/displayweave/android-update.json) |
| Source | `DisplayWeave-v0.3.5-source.tar.gz` | Tracked source at the release tag; hash in the checksum manifest |
| Checksums | `SHA256SUMS.txt` | Hashes all seven release files above |

Android signing certificate SHA-256:

```text
89805f045800ea18b56b84b32e8e31b1710a3c7bf3c85fda54d260d1fc6d589d
```

## Installation boundaries

- **Mac:** use the guided DMG or install the app from the ZIP. The app is signed with the continuing Apple Development identity but is not Developer ID notarized; follow the official first-run prompt if macOS blocks it. Sparkle authenticates later ZIP updates.
- **Android:** install over the existing package. Android may require the user's approval for unknown-app installation and presents its normal final confirmation.
- **iOS/iPadOS:** the IPA is unsigned and cannot be installed directly; a valid Apple signing identity is required.

The Android high-frame-rate trial and iPad native-resolution high-refresh option are experimental. Physical sustained refresh, two-device streaming, Intel runtime and endurance remain separate hardware acceptance items. The v0.3.4 Mac app was used as the signing-continuity baseline. See [local publication](local-release.md) and [Mac permission continuity](../guides/mac-permissions.md).

Local verified copies: `artifacts/releases/v0.3.5/`. The current binary hashes are checked against the release notes by `pnpm run check:release`.

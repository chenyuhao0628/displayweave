[English](current.md) | [简体中文](current.zh-CN.md)

# DisplayWeave `v0.3.4` Stable Release Distribution

[GitHub Release](https://github.com/chenyuhao0628/displayweave/releases/tag/v0.3.4)

2026-11-09: build 23 includes Android experimental high-FPS/background keep-alive work, the opt-in iPad native-resolution high-refresh trial, code hardening and rounded Mac icon tiles. Requested or negotiated FPS is not measured physical refresh. See the [release notes](v0.3.4.md).

| Platform/feed | Asset | SHA-256 or trust boundary |
| --- | --- | --- |
| macOS first install | `DisplayWeave-macOS.dmg` | `afb5f775f2dcee8765a5f1bb490659b6b85d9f4d10112fc5f1f2d8e44538a6c6`; pinned Apple Development signature, not notarized |
| macOS update | `DisplayWeave-macOS.zip` | `0b5d6e4c97bf77e2c0354b258e36950711e5a2ef35b1279c8bb191426c5c4db6`; EdDSA-authenticated Sparkle payload |
| Android | `DisplayWeave-Android.apk` | `30d06443d73c0b39157fb17e4a8ec97d2d56009fda2ad184a5a8c03e19230d4b`; v2 signed with the pinned project key |
| iOS/iPadOS | `DisplayWeave-iOS-unsigned-resigning-input.ipa` | `a23e19b9d34d340396439fa6833d8ec842c78f9c40121f088e66c18ba0ed12e9`; unsigned arm64 re-signing input |
| Mac update feed | `appcast.xml` | [Configured Sparkle feed](https://chenyuhao0628.github.io/displayweave/appcast.xml) |
| Android update feed | `android-update.json` | [Configured metadata feed](https://chenyuhao0628.github.io/displayweave/android-update.json) |
| Source | `DisplayWeave-v0.3.4-source.tar.gz` | Tracked source at the release tag; hash in the checksum manifest |
| Checksums | `SHA256SUMS.txt` | Hashes all seven release files above |

Android signing certificate SHA-256:

```text
89805f045800ea18b56b84b32e8e31b1710a3c7bf3c85fda54d260d1fc6d589d
```

## Installation boundaries

- **Mac:** use the guided DMG or install the app from the ZIP. The app is signed with the continuing Apple Development identity but is not Developer ID notarized; follow the official first-run prompt if macOS blocks it. Sparkle authenticates later ZIP updates.
- **Android:** install over the existing package. Android may require the user's approval for unknown-app installation and presents its normal final confirmation.
- **iOS/iPadOS:** the IPA is unsigned and cannot be installed directly; a valid Apple signing identity is required.

The Android high-frame-rate trial and iPad native-resolution high-refresh option are experimental. Physical sustained refresh, two-device streaming, Intel runtime and endurance remain separate hardware acceptance items. The v0.3.3 Mac app was downloaded and used as the signing-continuity baseline. See [local publication](local-release.md) and [Mac permission continuity](../guides/mac-permissions.md).

Local verified copies: `artifacts/releases/v0.3.4/`. The current binary hashes are checked against the release notes by `pnpm run check:release`.

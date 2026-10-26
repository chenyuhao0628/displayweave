[English](current.md) | [简体中文](current.zh-CN.md)

# DisplayWeave `v0.3.2` Stable Release Distribution

[GitHub Release](https://github.com/chenyuhao0628/displayweave/releases)

2026-10-26: stable build 21 adds iMac 4K/4.5K/5K desktop presets and explicit logical-size labels, isolates blocking encoder work, and adapts sustained Mac encoder pressure without changing desktop layout. Downloads use GitHub Releases only; Mac and Android update metadata uses the project GitHub Pages site. See the [release notes](v0.3.2.md) for changes, permission continuity and verification limits.

| Platform/feed | Asset | SHA-256 or trust boundary |
| --- | --- | --- |
| macOS first install | `DisplayWeave-macOS.dmg` | `566d0ee6e54dea4d5134f1f760836b0c1c9f6aa458fb517e10c8f531faba7fec`; pinned Apple Development signature, not notarized |
| macOS update | `DisplayWeave-macOS.zip` | `8177069330cc26f42587d0367759fd20e744f339dd6ca5f7ef27317e579afa74`; EdDSA-authenticated Sparkle payload |
| Android | `DisplayWeave-Android.apk` | `717cf4e73ec12cf82a8363b27ee495568a317835d57421faf4c8f93fd92dd0eb`; v2 signed with the pinned project key |
| iOS/iPadOS | `DisplayWeave-iOS-unsigned-resigning-input.ipa` | `f088b52ba9b2480256ea4c2b40994a86d6398603db9b6ada03ee83bca82bcb15`; unsigned re-signing input |
| Mac update feed | `appcast.xml` | [Configured Sparkle feed](https://chenyuhao0628.github.io/displayweave/appcast.xml) |
| Android update feed | `android-update.json` | [Configured metadata feed](https://chenyuhao0628.github.io/displayweave/android-update.json) |
| Source | `DisplayWeave-v0.3.2-source.tar.gz` | Tracked source at the release tag; hash in the checksum manifest |
| Checksums | `SHA256SUMS.txt` | Hashes all seven release files above |

Android signing certificate SHA-256:

```text
89805f045800ea18b56b84b32e8e31b1710a3c7bf3c85fda54d260d1fc6d589d
```

## One-time migration

- **Mac:** replace the previous app manually in `/Applications`. Because this
  release has no Developer ID notarization, verify the checksum and source,
  then use Control-click → Open or Privacy & Security → Open Anyway if needed.
  Later releases can use the EdDSA-authenticated Sparkle channel.
- **Android:** Older installations without the current updater must install this APK over the existing package once.
  Downloads come from the matching GitHub Release
  only. Every artifact is verified against the pinned
  package identity and certificate; unknown-source permission and final system
  installation confirmation are still required.
- **iOS/iPadOS:** the input is not directly installable. The user must provide
  a valid signing identity; this release does not add iOS automatic updates.

For reproducible, versioned builds and publication, follow [local publication](local-release.md) and [Mac permission continuity](../guides/mac-permissions.md). The Mac identity, Sparkle private key and Android keystore stay outside Git; passwords are read from Keychain without printing them. The first migration from ad-hoc Mac signing may require permission grants again. Later builds compare the previous release's designated requirement.

Apple Development signing supports this unnotarized release; it is not Developer ID notarization. The unsigned iOS input still requires the user's valid signing identity. DisplayWeave does not endorse third-party signing services.

This is a stable release; Mac-to-Mac performance remains experimental. It includes encrypted pairing, negotiated Apple refresh targets and main-screen OpenDisplay compatibility. Physical high-refresh performance, two simultaneous Android receivers, controlled USB/WiFi comparisons and 30-minute/2-hour endurance remain unverified for this build.

Local verified copies are kept in `artifacts/releases/v0.3.2/`. The seven-file manifest is verified against the published GitHub assets before old local versions are removed. The current binary hashes in this table are checked against the release notes by `pnpm run check:release`.

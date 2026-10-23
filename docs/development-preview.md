[English](development-preview.md) | [简体中文](development-preview.zh-CN.md)

# DisplayWeave `v0.3.0` Stable Release Distribution

[GitHub Release](https://github.com/chenyuhao0628/displayweave/releases)

2026-10-23: stable build 19 includes Mac 4K latency improvements, the 100 Mbps H.264 LAN ceiling and reviewed upstream recovery fixes, retaining the pinned Apple Development identity. Downloads use GitHub Releases only; Mac and Android update metadata uses the project GitHub Pages site. See the [release notes](release-notes-v0.3.0.md) for changes, permission continuity and verification limits.

| Platform/feed | Asset | SHA-256 or trust boundary |
| --- | --- | --- |
| macOS first install | `DisplayWeave-macOS.dmg` | `ef709366b3535188274b3ef74c3f39c104132d7b1a61f00ff8881401543163cb`; pinned Apple Development signature, not notarized |
| macOS update | `DisplayWeave-macOS.zip` | `dacd185cbbce90361e5eb1e95ff7ebdd838f55c5d3ac704814d95e023e7ffaca`; EdDSA-authenticated Sparkle payload |
| Android | `DisplayWeave-Android.apk` | `5db3982be3c8ef6b6fe8d3279b570d2173569c5a2041b5223527ccb3c536c763`; v2 signed with the pinned project key |
| iOS/iPadOS | `DisplayWeave-iOS-unsigned-resigning-input.ipa` | `9db070367ffe92ba4d77d5d8c574867dfce3e321e39b953ac5f3b5e9f1f86078`; unsigned re-signing input |
| Mac update feed | `appcast.xml` | [Configured Sparkle feed](https://chenyuhao0628.github.io/displayweave/appcast.xml) |
| Android update feed | `android-update.json` | [Configured metadata feed](https://chenyuhao0628.github.io/displayweave/android-update.json) |
| Source | `DisplayWeave-v0.3.0-source.tar.gz` | Tracked source at the release tag; hash in the checksum manifest |
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
- **Android:** p5 must install this APK manually over the existing package once.
  Downloads come from the matching GitHub Release
  only. Every artifact is verified against the pinned
  package identity and certificate; unknown-source permission and final system
  installation confirmation are still required.
- **iOS/iPadOS:** the input is not directly installable. The user must provide
  a valid signing identity; this release does not add iOS automatic updates.

For reproducible, versioned builds and publication, follow [local publication](local-release.md) and [Mac permission continuity](mac-permissions.md). The Mac identity, Sparkle private key and Android keystore stay outside Git; passwords are read from Keychain without printing them. The first migration from ad-hoc Mac signing may require permission grants again. Later builds compare the previous release's designated requirement.

Apple Development signing supports this unnotarized release; it is not Developer ID notarization. The unsigned iOS input still requires the user's valid signing identity. DisplayWeave does not endorse third-party signing services.

This is a stable release; Mac-to-Mac performance remains experimental. It includes encrypted pairing, negotiated Apple refresh targets and main-screen OpenDisplay compatibility. Physical high-refresh performance, two simultaneous Android receivers, controlled USB/WiFi comparisons and 30-minute/2-hour endurance remain unverified for this build.

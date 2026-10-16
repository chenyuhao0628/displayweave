[English](development-preview.md) | [简体中文](development-preview.zh-CN.md)

# DisplayWeave `v0.3.0-preview.3` Development Distribution

[GitHub Release](https://github.com/chenyuhao0628/displayweave/releases)

2026-10-17: build 18 uses a pinned Apple Development identity for macOS. Downloads use GitHub Releases only; Mac and Android update metadata uses the project GitHub Pages site. See the [release notes](release-notes-v0.3.0-preview.3.md) for permission continuity, retained OpenDisplay compatibility and build evidence.

| Platform/feed | Asset | SHA-256 or trust boundary |
| --- | --- | --- |
| macOS first install | `DisplayWeave-macOS.dmg` | `a29756e94f48f7eeab5968ed9c03e5aebaf0b74e743d69200748195dc6431518`; pinned Apple Development signature, not notarized |
| macOS update | `DisplayWeave-macOS.zip` | `b3a0a5e7d7dea6e9e487bd7e1f6b89e7bd3f3ddd597febbd99d7bf5276f41bd7`; EdDSA-authenticated Sparkle payload |
| Android | `DisplayWeave-Android.apk` | `370e1ba6b40cbeb9a66a3cfca280d0c5f9ab710d7b3d4a9468c4238c78646bf8`; v2 signed with the pinned project key |
| iOS/iPadOS | `DisplayWeave-Preview-0.1-iOS-unsigned-resigning-input.ipa` | `83328fc764068b365b6726439c9a9f10dd22502a4244d74cbf7c78d5e862a29c`; unsigned re-signing input |
| Mac update feed | `appcast.xml` | [Configured Sparkle feed](https://chenyuhao0628.github.io/displayweave/appcast.xml) |
| Android update feed | `android-update.json` | [Configured metadata feed](https://chenyuhao0628.github.io/displayweave/android-update.json) |
| Source | `DisplayWeave-v0.3.0-preview.3-source.tar.gz` | Tracked source at the release tag; hash in the checksum manifest |
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

Apple Development signing supports this unnotarized preview; it is not Developer ID notarization. The unsigned iOS input still requires the user's valid signing identity. DisplayWeave does not endorse third-party signing services.

This remains a development preview. It includes encrypted pairing, negotiated Apple refresh targets and main-screen OpenDisplay compatibility. Physical high-refresh performance, two simultaneous Android receivers, controlled USB/WiFi comparisons and 30-minute/2-hour endurance remain unverified for this build.

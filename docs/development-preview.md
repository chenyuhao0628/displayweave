[English](development-preview.md) | [简体中文](development-preview.zh-CN.md)

# DisplayWeave `v0.3.0-preview.2` Development Distribution

[GitHub Release](https://github.com/chenyuhao0628/displayweave/releases)

2026-10-16: this preview is built locally. Downloads use GitHub Releases only; Mac and Android update metadata uses the project GitHub Pages site, which is available again. See the [release notes](release-notes-v0.3.0-preview.2.md) for UI changes, OpenDisplay compatibility and build evidence.

| Platform/feed | Asset | SHA-256 or trust boundary |
| --- | --- | --- |
| macOS first install | `DisplayWeave-macOS.dmg` | `2354ed9f43723b32c74999efffe11ba950f49699a45a8b17a8c64b71ad7f7305`; ad-hoc signed and not notarized |
| macOS update | `DisplayWeave-macOS.zip` | `8a1368123ed65cd4e4fea6912e62db5d40f6da7dc239bdf18b8312ff8216b8d1`; EdDSA-authenticated Sparkle payload |
| Android | `DisplayWeave-Android.apk` | `cd00fd37422ff16c9d9b8860abb062dd98b0519dadb0c3fd3047532ecf41fab0`; v2 signed with the pinned project key |
| iOS/iPadOS | `DisplayWeave-Preview-0.1-iOS-unsigned-resigning-input.ipa` | `50d0c7a7cadc49fc64bf79dc71afd3f6c755d59ac968307135e58f445d68a582`; unsigned re-signing input |
| Mac update feed | `appcast.xml` | [Configured Sparkle feed](https://chenyuhao0628.github.io/displayweave/appcast.xml) |
| Android update feed | `android-update.json` | [Configured metadata feed](https://chenyuhao0628.github.io/displayweave/android-update.json) |
| Source | `DisplayWeave-v0.3.0-preview.2-source.tar.gz` | Tracked source at the release tag; hash in the checksum manifest |
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
  only as an availability fallback. Every artifact is verified against the pinned
  package identity and certificate; unknown-source permission and final system
  installation confirmation are still required.
- **iOS/iPadOS:** the input is not directly installable. The user must provide
  a valid signing identity; this release does not add iOS automatic updates.

Install the pinned DMG metadata dependencies with
`python3 -m pip install -r tools/dmg-requirements.txt`, then build the local
package set with `./tools/package-preview-0.1.sh`. The Android
keystore lives under `~/Library/Application Support/DisplayWeave/Signing/` and
its password is stored in Keychain. Neither belongs in Git. A free Apple
Personal Team is suitable only for maintainer testing on registered devices,
not general public distribution. DisplayWeave does not endorse third-party
signing services.

This remains a development preview. It includes encrypted pairing, negotiated Apple refresh targets and main-screen OpenDisplay compatibility. Physical high-refresh performance, two simultaneous Android receivers, controlled USB/WiFi comparisons and 30-minute/2-hour endurance remain unverified for this build.

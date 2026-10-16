[English](development-preview.md) | [简体中文](development-preview.zh-CN.md)

# DisplayWeave `v0.3.0-preview.1` Development Distribution

[GitHub Release](https://github.com/chenyuhao0628/displayweave/releases)

2026-10-16: this preview is built locally. Downloads use GitHub Releases only; Mac and Android update metadata uses the project GitHub Pages site, which is available again. See the [release notes](release-notes-v0.3.0-preview.1.md) for build evidence and the required pairing migration.

| Platform/feed | Asset | SHA-256 or trust boundary |
| --- | --- | --- |
| macOS first install | `DisplayWeave-macOS.dmg` | `f3c043d53cce3b459ce36f62ea640e70dfce9a3c9165cf2ec0326ee9d6b4579a`; ad-hoc signed and not notarized |
| macOS update | `DisplayWeave-macOS.zip` | `a83e6a0a0455bfe7f0c0a5b5cb70f4a1acdbc18b1f8f00c3e76f9eea419ac67c`; EdDSA-authenticated Sparkle payload |
| Android | `DisplayWeave-Android.apk` | `3f909af1bd0e6da09a72048b124d061aadd8284c2dad7beb0b8a3e7f568a098e`; v2 signed with the pinned project key |
| iOS/iPadOS | `DisplayWeave-Preview-0.1-iOS-unsigned-resigning-input.ipa` | `8e423d4c6baf60d3b92c990f1d465473c223bce539baf3456abf59799f079bd1`; unsigned re-signing input |
| Mac update feed | `appcast.xml` | [Configured Sparkle feed](https://chenyuhao0628.github.io/displayweave/appcast.xml) |
| Android update feed | `android-update.json` | [Configured metadata feed](https://chenyuhao0628.github.io/displayweave/android-update.json) |
| Source | `DisplayWeave-v0.3.0-preview.1-source.tar.gz` | Tracked source at the release tag; hash in the checksum manifest |
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

This remains a development preview. It does not provide encrypted WiFi pairing,
iOS/iPadOS 120Hz, a completed two-Android test, a controlled same-condition
USB/WiFi benchmark, or completed 30-minute/2-hour endurance evidence.

[English](development-preview.md) | [简体中文](development-preview.zh-CN.md)

# DisplayWeave `v0.2.0-preview.2` Development Distribution

[GitHub prerelease](https://github.com/chenyuhao0628/displayweave/releases/tag/v0.2.0-preview.2)

| Platform/feed | Asset | SHA-256 or trust boundary |
| --- | --- | --- |
| macOS | `DisplayWeave-macOS.zip` | `0c0bbd61625a90ef5264097da3f25db0d77c1383421e506a97aab0c6eb50b501`; ad-hoc signed and not notarized |
| Android | `DisplayWeave-Android.apk` | `04a7433deb4fa893ef95f216d9b4e35e01ff5466bda56d801b88792b0122b2e1`; v2 signed with the pinned project key |
| iOS/iPadOS | `DisplayWeave-Preview-0.1-iOS-unsigned-resigning-input.ipa` | `7a188576fec361daff62efbbb978f9800ae4fac55d269ffbfecb1806646289f4`; unsigned re-signing input |
| Mac update feed | `appcast.xml` | [Live Sparkle feed](https://chenyuhao0628.github.io/displayweave/appcast.xml) |
| Android update feed | `android-update.json` | [Live verified metadata](https://chenyuhao0628.github.io/displayweave/android-update.json) |
| Checksums | `SHA256SUMS.txt` | Hashes all five release files above |

Android signing certificate SHA-256:

```text
89805f045800ea18b56b84b32e8e31b1710a3c7bf3c85fda54d260d1fc6d589d
```

## One-time migration

- **Mac:** replace the previous app manually in `/Applications`. Because this
  release has no Developer ID notarization, verify the checksum and source,
  then use Control-click → Open or Privacy & Security → Open Anyway if needed.
  Later releases can use the EdDSA-authenticated Sparkle channel.
- **Android:** install this APK over the existing package. Later in-app
  downloads are verified against the pinned package identity and certificate,
  but unknown-source permission and final system installation confirmation are
  still required. DisplayWeave cannot silently install an APK.
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

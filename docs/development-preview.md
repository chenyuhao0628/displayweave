[English](development-preview.md) | [简体中文](development-preview.zh-CN.md)

# DisplayWeave `v0.2.1-p7` Development Distribution

[GitHub Release](https://github.com/chenyuhao0628/displayweave/releases/tag/v0.2.1-p7)

| Platform/feed | Asset | SHA-256 or trust boundary |
| --- | --- | --- |
| macOS first install | `DisplayWeave-macOS.dmg` | `26e9cf259410e731acfbe1a682444b71bf73d679298db6b00d82b3bef15ce0f6`; ad-hoc signed and not notarized |
| macOS update | `DisplayWeave-macOS.zip` | `dae40c3df8f9bbdebdce0484621a7d7a6a4c99c1b1a8504e9096fc8863705aef`; EdDSA-authenticated Sparkle payload |
| Android | `DisplayWeave-Android.apk` | `ac1b5081259647c248e8c5d69aff4f477f4ebc9044a70c4a4602f6c81d6c2381`; v2 signed with the pinned project key |
| iOS/iPadOS | `DisplayWeave-Preview-0.1-iOS-unsigned-resigning-input.ipa` | `634305344f5cd7433a74a95166f781ea7313d5473ded88918528a3895e8eb1eb`; unsigned re-signing input |
| Mac update feed | `appcast.xml` | [Live Sparkle feed](https://chenyuhao0628.github.io/displayweave/appcast.xml) |
| Android update feed | `android-update.json` | [Live verified metadata](https://chenyuhao0628.github.io/displayweave/android-update.json) |
| Checksums | `SHA256SUMS.txt` | Hashes all six release files above |

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
  p6 and later download from Cloudflare first and use the matching GitHub Release
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

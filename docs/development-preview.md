[English](development-preview.md) | [简体中文](development-preview.zh-CN.md)

# DisplayWeave `v0.2.0-preview.3` Development Distribution

[GitHub prerelease](https://github.com/chenyuhao0628/displayweave/releases/tag/v0.2.0-preview.3)

| Platform/feed | Asset | SHA-256 or trust boundary |
| --- | --- | --- |
| macOS first install | `DisplayWeave-macOS.dmg` | `68b3737f09f8d02da135aef89167896aa4057d453d65fa20861e2ae58a142a29`; ad-hoc signed and not notarized |
| macOS update | `DisplayWeave-macOS.zip` | `32cade719d825d3f3562483cb72b9a4d65223e4b2518d54389ff2d661a1742ae`; EdDSA-authenticated Sparkle payload |
| Android | `DisplayWeave-Android.apk` | `98356346793932bd494a31585ff7ca788b880bd62cd6b8e2762aadc8ff0541c1`; v2 signed with the pinned project key |
| iOS/iPadOS | `DisplayWeave-Preview-0.1-iOS-unsigned-resigning-input.ipa` | `7eb93eedd24e44bbabccb38ab145a2e2122e4c53bd52dbe8e9d2b3d08e21eb16`; unsigned re-signing input |
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

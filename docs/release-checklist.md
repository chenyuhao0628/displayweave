[English](release-checklist.md) | [简体中文](release-checklist.zh-CN.md)

# `v0.2.0-preview.2` release checklist

## Published identity

- Release: https://github.com/chenyuhao0628/displayweave/releases/tag/v0.2.0-preview.2
- Version: `v0.2.0-preview.2`
- Monotonic build/version code: `3`
- Release target commit: `adcc576f0b8667385b35ae04a76e8d5b9848c721`
- Public feed commit: `66d2dcfaa26297cc4e3cb7059e367a018eaa74ad`
- Successful Pages run: `29300403928`

## Assets and integrity

| Asset | SHA-256 / check |
| --- | --- |
| `DisplayWeave-macOS.zip` | `0c0bbd61625a90ef5264097da3f25db0d77c1383421e506a97aab0c6eb50b501` |
| `DisplayWeave-Android.apk` | `04a7433deb4fa893ef95f216d9b4e35e01ff5466bda56d801b88792b0122b2e1` |
| `DisplayWeave-Preview-0.1-iOS-unsigned-resigning-input.ipa` | `7a188576fec361daff62efbbb978f9800ae4fac55d269ffbfecb1806646289f4` |
| `appcast.xml` | `523252198c6bbd987281a9a60225576a53ba18e1f6421fbb2604be837868ec1f` |
| `android-update.json` | `25764708231ddcbc3f8eb7796a7ce8a9108ca10a9bee06665ccba2c49da09bd1` |
| `SHA256SUMS.txt` | Present and covers the five files above |

Android signing certificate SHA-256:

```text
89805f045800ea18b56b84b32e8e31b1710a3c7bf3c85fda54d260d1fc6d589d
```

- [x] Mac app is ad-hoc signed, universal, and intentionally not notarized.
- [x] Android APK is v2 signed with one signer and the pinned certificate.
- [x] iOS IPA is an unsigned arm64 re-signing input and is not directly installable.
- [x] Release assets are immutable; future fixes require a higher build.

## Build and automated verification

- [x] 17 Swift tests passed.
- [x] 6 Android self-tests passed.
- [x] Mac, iOS compatibility, and Android Release builds completed.
- [x] Archive structure, displayed version, build/version code, update URLs,
  byte counts, hashes, Android package identity, and signing were checked.
- [x] Invalid Sparkle signatures, modified Android downloads, wrong package
  identity, and non-increasing versions are rejected by the corresponding path.

## Update-channel checks

- [x] Live Mac feed:
  https://chenyuhao0628.github.io/displayweave/appcast.xml
- [x] Live Android feed:
  https://chenyuhao0628.github.io/displayweave/android-update.json
- [x] Mac first-install instructions disclose Gatekeeper, ad-hoc signing, and
  lack of notarization.
- [x] Android first-install instructions disclose unknown-source permission and
  mandatory system confirmation; no silent installation is claimed.
- [x] Key-loss recovery and feed rollback procedures are documented in
  [automatic updates](automatic-updates.md).

## iOS/OpenDisplay compatibility

- [x] `_opensidecar._tcp` discovery and TCP port `9000` remain unchanged.
- [x] Four-byte length-prefix framing, Annex B H.264, and legacy hello defaults
  remain available.
- [x] The Metal drawable synchronization fix covers the reported iPhone black
  screen path without changing the receiver protocol.
- [x] iOS remains outside the Mac/Android automatic-update channel.

## Deferred physical evidence

- [ ] Complete a run with two Android devices.
- [ ] Complete a controlled same-condition USB/WiFi matrix.
- [ ] Complete the planned 30-minute and 2-hour endurance runs.

The OnePlus high-refresh/recovery and iPhone observations in the
[Preview 2 stability report](stability-test-report.md) remain prior evidence;
they were not rerun for this publication.

[English](release-checklist.md) | [简体中文](release-checklist.zh-CN.md)

# `v0.2.0-preview.3` release checklist

## Published identity

- Release: https://github.com/chenyuhao0628/displayweave/releases/tag/v0.2.0-preview.3
- Version: `v0.2.0-preview.3`
- Monotonic build/version code: `4`
- Release target commit: `1f159b44f256f64da53ae2c8cc3c1b96754bcad3`
- Public feed commit: `dbf730bd01d26df18a5717e34fb86d0b38b8809c`
- Successful Release run: `29323273404`
- Successful Pages run: `29323640794`

## Assets and integrity

| Asset | SHA-256 / check |
| --- | --- |
| `DisplayWeave-macOS.zip` | `32cade719d825d3f3562483cb72b9a4d65223e4b2518d54389ff2d661a1742ae` |
| `DisplayWeave-macOS.dmg` | `68b3737f09f8d02da135aef89167896aa4057d453d65fa20861e2ae58a142a29` |
| `DisplayWeave-Android.apk` | `98356346793932bd494a31585ff7ca788b880bd62cd6b8e2762aadc8ff0541c1` |
| `DisplayWeave-Preview-0.1-iOS-unsigned-resigning-input.ipa` | `7eb93eedd24e44bbabccb38ab145a2e2122e4c53bd52dbe8e9d2b3d08e21eb16` |
| `appcast.xml` | `3606e4f32678319f1bcea1e94e97bcba1a1171a6810ed935be3b00264f4795c8` |
| `android-update.json` | `90adbfe6345de384c8541b986673cae28c256a6cef8017e000fb93ff7cfdbf70` |
| `SHA256SUMS.txt` | Present and covers the six files above |

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

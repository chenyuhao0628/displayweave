[English](release-checklist.md) | [简体中文](release-checklist.zh-CN.md)

# `v0.2.0-preview.1` release checklist

## Published identity

- Release: https://github.com/chenyuhao0628/displayweave/releases/tag/v0.2.0-preview.1
- Version: `v0.2.0-preview.1`
- Monotonic build/version code: `2`
- Release target commit: `bb50d919beae57db893222565e6b2980afb21ff3`
- Public feed commit: `b8e22c8137bb71e58699f785517a4dd338ccdc72`
- Successful Pages run: `29269282121`

## Assets and integrity

| Asset | SHA-256 / check |
| --- | --- |
| `DisplayWeave-macOS.zip` | `35c828abc9200affe8a63602519f63e56ca7aff4ca6a88d6bbcb2f2bf009bec5` |
| `DisplayWeave-Android.apk` | `24588906ccde36958355d8e72bae54fa1e6f8244c3fca832b81c9a05bd7519d9` |
| `DisplayWeave-Preview-0.1-iOS-unsigned-resigning-input.ipa` | `fee1b7d8c1b81bac33b91b11dfaeeb608ccc35050ccc4bcd796178227acdedfa` |
| `appcast.xml` | `efc966fd6f051417a6f06bf12fe31edca9d8728fa19ae730619e694a1df1d250` |
| `android-update.json` | `453c7e27ed3c261cfbca5f5bf1ba7c4d8861f7c0563cf8fc207254185176bf38` |
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

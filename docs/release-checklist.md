[English](release-checklist.md) | [简体中文](release-checklist.zh-CN.md)

# `v0.2.1-p1` release checklist

## Published identity

- Release: https://github.com/chenyuhao0628/displayweave/releases/tag/v0.2.1-p1
- Version: `v0.2.1-p1`
- Monotonic Mac build / Android version code: `8`
- Release tag target commit: `2fb57b4b341c85104a4f1a6e8cf0ecd08dd6754f`
- Successful pre-release CI run: `29383103136`
- Successful Release run: `29383334404`
- Successful build job: `87251419579`
- Successful Pages/update-feed job: `87251982032`

## Assets and integrity

| Asset | SHA-256 / check |
| --- | --- |
| `DisplayWeave-macOS.zip` | `702e1857335eb3349d301cfd9085718c03e9f6cdb933dfd16bf7b382dfa1dd91` |
| `DisplayWeave-macOS.dmg` | `993b7e7e8969cf377eb6500fa9681f51a2761ca493bd77c1ff5ada94ebc51b5c` |
| `DisplayWeave-Android.apk` | `0c77365c49647813a0a9a2aeff217cab550432b028d66c3b19398ba043f65140` |
| `DisplayWeave-Preview-0.1-iOS-unsigned-resigning-input.ipa` | `4502da624205b526334c05452389d2b2ba9130582bd7a136b6831db8d029b964` |
| `appcast.xml` | `1ec636ab38f9cc8ac6e72e6aee795316ad33f679916f507e363d84f1da4e3412` |
| `android-update.json` | `cf9269e9971bcae3890799ef062b4ae89fe40adeff0231daf9972012374ac005` |
| `SHA256SUMS.txt` | Present and covers the six files above |

Android signing certificate SHA-256:

```text
89805f045800ea18b56b84b32e8e31b1710a3c7bf3c85fda54d260d1fc6d589d
```

- [x] GitHub reports all seven immutable assets uploaded.
- [x] Mac app is ad-hoc signed, universal, and intentionally not notarized.
- [x] Android APK is v2 signed with one signer and the pinned certificate.
- [x] iOS IPA is an unsigned arm64 re-signing input and is not directly installable.

## Build and automated verification

- [x] Manually dispatched workflow used `release_tag=v0.2.1-p1` and `build_number=8`.
- [x] Workflow head and Release tag target both equal `2fb57b4b341c85104a4f1a6e8cf0ecd08dd6754f`.
- [x] Mac Release and unsigned iOS compatibility builds completed.
- [x] Android signed Release build and all six Android self-test groups completed successfully.
- [x] `apksigner` reported v2 signing, one signer, and the pinned certificate.
- [x] Archive structure, displayed versions, update URLs, sizes, hashes, package identity, and signing passed `verify-update-release.sh`.
- [x] The target commit had already passed all 22 standalone Swift tests, Android's 61-task Debug build, unsigned macOS/iOS Debug builds, and the production site/docs checks.

## Update-channel checks

- [x] Live Mac feed: https://chenyuhao0628.github.io/displayweave/appcast.xml
- [x] Live Android feed: https://chenyuhao0628.github.io/displayweave/android-update.json
- [x] Android's live feed is byte-for-byte identical to its Release asset. The live repository-backed Sparkle XML differs only by its trailing newline; version, build, URL, length, and EdDSA enclosure signature match the Release asset.
- [x] Mac feed advertises short version `0.2.1-p1`, build `8`, ZIP size `2739581`, and the Release EdDSA signature.
- [x] Android feed advertises version code `8`, APK size `219380`, the expected package, SHA-256, minimum SDK, and pinned certificate.
- [x] Repository `public/` feeds contain the same values so later Pages deployments cannot roll the update channel back to Preview 5.
- [x] Release run `29383334404` overlaid the signed feeds and deployed them successfully; the repository feeds are persisted at `0.2.1-p1 (8)` to prevent a later rollback.

## Compatibility and disclosure

- [x] Legacy OpenDisplay iOS continues to use length-prefix + JSON telemetry + Annex-B H.264 unless Android-only capabilities are negotiated.
- [x] First-install instructions disclose Gatekeeper/ad-hoc signing, Android unknown-source confirmation, and the unsigned iOS boundary.
- [x] Release notes distinguish code/build evidence from pending physical evidence and make no unsupported latency claim.
- [x] English/Chinese Release links use absolute GitHub paths; the Simplified Chinese source is published at `docs/release-notes-v0.2.1-p1.zh-CN.md`.

## Deferred physical evidence

- [ ] Run the complete Android quick-recovery V2 matrix on attached hardware.
- [ ] Complete a controlled same-condition USB/WiFi matrix.
- [ ] Recheck a Legacy OpenDisplay iOS/TestFlight runtime.
- [ ] Complete a run with two Android devices.
- [ ] Complete the planned 30-minute and 2-hour endurance runs.
- [ ] Repeat disconnect/reconnect timing and stale-connection callback stress on attached receivers.

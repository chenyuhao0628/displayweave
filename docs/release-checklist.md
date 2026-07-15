[English](release-checklist.md) | [简体中文](release-checklist.zh-CN.md)

# `v0.2.1` release checklist

## Published identity

- Release: https://github.com/chenyuhao0628/displayweave/releases/tag/v0.2.1
- Version: `v0.2.1`
- Monotonic Mac build / Android version code: `7`
- Release tag target commit: `80c923fb24e9c23399128262bf65727886d1c5a0`
- Successful Release run: `29355318964`
- Successful build job: `87161369291`
- Successful Pages/update-feed job: `87162225134`
- Successful post-release CI run: `29356107557`

## Assets and integrity

| Asset | SHA-256 / check |
| --- | --- |
| `DisplayWeave-macOS.zip` | `ee507c6d3b4ddd80c7bdf3142ffe268cc06d5539950cd9298207c30de3a836fe` |
| `DisplayWeave-macOS.dmg` | `fc2964c6f5a7088269b5b6637db2df2d0fc3dc95abd134d427a998b8fa976fc1` |
| `DisplayWeave-Android.apk` | `3b0d0e3be13ea195867573746cf1938bc835f654391770b7269c3fbdfbbb494a` |
| `DisplayWeave-Preview-0.1-iOS-unsigned-resigning-input.ipa` | `50dd56b234c54d1e57aa64e7941eb2fe88e70640a128da284decb25cb850114e` |
| `appcast.xml` | `04111c2406e9efab99756604eb8bcc91abbb7a89de51117e26291f4c9a0c0cd9` |
| `android-update.json` | `b8383d74f91a066fa68734990a7250b4bc6c23d13e487035cb452c70de0f572c` |
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

- [x] Manually dispatched workflow used `release_tag=v0.2.1` and `build_number=7`.
- [x] Workflow head and Release tag target both equal `80c923fb24e9c23399128262bf65727886d1c5a0`.
- [x] Mac Release and unsigned iOS compatibility builds completed.
- [x] Android signed Release build and all six Android self-test groups completed successfully.
- [x] `apksigner` reported v2 signing, one signer, and the pinned certificate.
- [x] Archive structure, displayed versions, update URLs, sizes, hashes, package identity, and signing passed `verify-update-release.sh`.
- [x] The target commit had already passed all 22 standalone Swift tests, Android's 61-task Debug build, unsigned macOS/iOS Debug builds, and the production site/docs checks.

## Update-channel checks

- [x] Live Mac feed: https://chenyuhao0628.github.io/displayweave/appcast.xml
- [x] Live Android feed: https://chenyuhao0628.github.io/displayweave/android-update.json
- [x] Android's live feed is byte-for-byte identical to its Release asset. The live repository-backed Sparkle XML differs only by its trailing newline; version, build, URL, length, and EdDSA enclosure signature match the Release asset.
- [x] Mac feed advertises short version `0.2.1`, build `7`, ZIP size `2723141`, and the Release EdDSA signature.
- [x] Android feed advertises version code `7`, APK size `216324`, the expected package, SHA-256, minimum SDK, and pinned certificate.
- [x] Repository `public/` feeds contain the same values so later Pages deployments cannot roll the update channel back to Preview 5.
- [x] A post-release Pages deployment initially exposed the stale Preview 5 repository feeds; persistence commit `0259c1a` corrected them, and the live feeds were rechecked as `0.2.1 (7)`.

## Compatibility and disclosure

- [x] Legacy OpenDisplay iOS continues to use length-prefix + JSON telemetry + Annex-B H.264 unless Android-only capabilities are negotiated.
- [x] First-install instructions disclose Gatekeeper/ad-hoc signing, Android unknown-source confirmation, and the unsigned iOS boundary.
- [x] Release notes distinguish code/build evidence from pending physical evidence and make no unsupported latency claim.
- [x] English/Chinese Release links use absolute GitHub paths and the Simplified Chinese page returns HTTP 200.

## Deferred physical evidence

- [ ] Run the complete Android quick-recovery V2 matrix on attached hardware.
- [ ] Complete a controlled same-condition USB/WiFi matrix.
- [ ] Recheck a Legacy OpenDisplay iOS/TestFlight runtime.
- [ ] Complete a run with two Android devices.
- [ ] Complete the planned 30-minute and 2-hour endurance runs.
- [ ] Repeat disconnect/reconnect timing and stale-connection callback stress on attached receivers.

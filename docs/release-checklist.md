[English](release-checklist.md) | [简体中文](release-checklist.zh-CN.md)

# `v0.2.0-preview.4` release checklist

## Published identity

- Release: https://github.com/chenyuhao0628/displayweave/releases/tag/v0.2.0-preview.4
- Version: `v0.2.0-preview.4`
- Monotonic Mac build / Android version code: `5`
- Release target commit: `f300f88e84423f2a895d8b15dc3e514362e050bc`
- Successful Release run: `29347755688`
- Successful build job: `87135822940`
- Successful Pages/update-feed job: `87136937478`

## Assets and integrity

| Asset | SHA-256 / check |
| --- | --- |
| `DisplayWeave-macOS.zip` | `28cc452cce5168db3813834f59fbb0ad290ac7a30cba83c5f79337bb5cf36a8a` |
| `DisplayWeave-macOS.dmg` | `a41539f180a2d1854307d70cfaa7328ec14348bdee7ce242e9e478df0f265c50` |
| `DisplayWeave-Android.apk` | `11f3b7ce1e765aced8d1dfd255edfda83641f36db0863f37c6a948305e5c7820` |
| `DisplayWeave-Preview-0.1-iOS-unsigned-resigning-input.ipa` | `a43b7b99c861f9d4f60c85f0ce0bcc57e21c428fb106317df89a42fe8966d15a` |
| `appcast.xml` | `4eedf2ce46dc4908de8b8a414f8dd860d8a09042c2cdc9c206dc360428d37049` |
| `android-update.json` | `c225d438f89c615d167a3448016626205a20bb6d12190c58b48742283b33dceb` |
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

- [x] Manually dispatched workflow used `release_tag=v0.2.0-preview.4` and `build_number=5`.
- [x] Workflow head and Release target both equal `f300f88e84423f2a895d8b15dc3e514362e050bc`.
- [x] Mac Release and unsigned iOS compatibility builds completed.
- [x] Android signed Release build completed: 72 actionable tasks and all six Android self-test groups passed.
- [x] `apksigner` reported v2 signing, one signer, and the pinned certificate.
- [x] Archive structure, displayed versions, update URLs, sizes, hashes, package identity, and signing passed `verify-update-release.sh`.
- [x] The target commit had already passed all 22 standalone Swift tests, Android's 61-task Debug build, unsigned macOS/iOS Debug builds, and the production site/docs checks.

## Update-channel checks

- [x] Live Mac feed: https://chenyuhao0628.github.io/displayweave/appcast.xml
- [x] Live Android feed: https://chenyuhao0628.github.io/displayweave/android-update.json
- [x] Both live files were compared byte-for-byte with their Release assets after deployment.
- [x] Mac feed advertises short version `0.2.0-preview.4`, build `5`, ZIP size `2714987`, and the new EdDSA signature.
- [x] Android feed advertises version code `5`, APK size `213308`, the expected package, SHA-256, minimum SDK, and pinned certificate.
- [x] Repository `public/` feeds contain the same values so later Pages deployments cannot roll the update channel back to preview.3.

## Compatibility and disclosure

- [x] Legacy OpenDisplay iOS continues to use length-prefix + JSON telemetry + Annex-B H.264 unless Android-only capabilities are negotiated.
- [x] First-install instructions disclose Gatekeeper/ad-hoc signing, Android unknown-source confirmation, and the unsigned iOS boundary.
- [x] Release notes distinguish code/build evidence from pending physical evidence and make no unsupported latency claim.

## Deferred physical evidence

- [ ] Run the complete Android quick-recovery V2 matrix on attached hardware.
- [ ] Complete a controlled same-condition USB/WiFi matrix.
- [ ] Recheck a Legacy OpenDisplay iOS/TestFlight runtime.
- [ ] Complete a run with two Android devices.
- [ ] Complete the planned 30-minute and 2-hour endurance runs.

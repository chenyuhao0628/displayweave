[English](release-checklist.md) | [简体中文](release-checklist.zh-CN.md)

# `v0.2.1-p2` release checklist

## Published identity

- Release: https://github.com/chenyuhao0628/displayweave/releases/tag/v0.2.1-p2
- Version: `v0.2.1-p2`
- Monotonic Mac build / Android version code: `9`
- Release tag target commit: `cddaaad248a89ec3a4b387fb8a38cb090681895e`
- Successful pre-release CI run: `29384709884`
- Successful Release run: `29384932159`
- Successful build job: `87256105382`
- Successful Pages/update-feed job: `87256476833`

## Assets and integrity

| Asset | SHA-256 / check |
| --- | --- |
| `DisplayWeave-macOS.zip` | `2a009eb1cdade8ac532a826a78d00f75cbb2d526c41742e6d849bfc4691294b7` |
| `DisplayWeave-macOS.dmg` | `09d09270e332e705a0b9088f84b7e709a4b560dce56f157c04278fd6a6bde633` |
| `DisplayWeave-Android.apk` | `28efb42c0f8459ee5aabf4702369ae6cacfd691c0251fef25e2b9d1101376390` |
| `DisplayWeave-Preview-0.1-iOS-unsigned-resigning-input.ipa` | `4580df6a947aa94da3ab9f237e72a9ff60211ce15a7a1660f1a4177325d19f99` |
| `appcast.xml` | `6f2f1f322c7bdbe7db8ba0d9b442594251cde23b6ba116e2a7405e1b650aaa3f` |
| `android-update.json` | `0ac96cbcf9991248dc79338c1a85f86120ba645aa4fee858d06ad3ff76f8ee12` |
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

- [x] Manually dispatched workflow used `release_tag=v0.2.1-p2` and `build_number=9`.
- [x] Workflow head and Release tag target both equal `cddaaad248a89ec3a4b387fb8a38cb090681895e`.
- [x] Mac Release and unsigned iOS compatibility builds completed.
- [x] Android signed Release build and all six Android self-test groups completed successfully.
- [x] `apksigner` reported v2 signing, one signer, and the pinned certificate.
- [x] Archive structure, displayed versions, update URLs, sizes, hashes, package identity, and signing passed `verify-update-release.sh`.
- [x] The target commit had already passed all 22 standalone Swift tests, Android's 61-task Debug build, unsigned macOS/iOS Debug builds, and the production site/docs checks.

## Update-channel checks

- [x] Live Mac feed: https://chenyuhao0628.github.io/displayweave/appcast.xml
- [x] Live Android feed: https://chenyuhao0628.github.io/displayweave/android-update.json
- [x] Android's live feed is byte-for-byte identical to its Release asset. The live repository-backed Sparkle XML differs only by its trailing newline; version, build, URL, length, and EdDSA enclosure signature match the Release asset.
- [x] Mac feed advertises short version `0.2.1-p2`, build `9`, ZIP size `2739582`, and the Release EdDSA signature.
- [x] Android feed advertises version code `9`, APK size `222164`, the expected package, SHA-256, minimum SDK, and pinned certificate.
- [x] Repository `public/` feeds contain the same values so later Pages deployments cannot roll the update channel back to Preview 5.
- [x] Release run `29384932159` overlaid the signed feeds and deployed them successfully; the repository feeds are persisted at `0.2.1-p2 (9)` to prevent a later rollback.

## Compatibility and disclosure

- [x] Legacy OpenDisplay iOS continues to use length-prefix + JSON telemetry + Annex-B H.264 unless Android-only capabilities are negotiated.
- [x] First-install instructions disclose Gatekeeper/ad-hoc signing, Android unknown-source confirmation, and the unsigned iOS boundary.
- [x] Release notes distinguish code/build evidence from pending physical evidence and make no unsupported latency claim.
- [x] English/Chinese Release links use absolute GitHub paths; the Simplified Chinese source is published at `docs/release-notes-v0.2.1-p2.zh-CN.md`.

## Deferred physical evidence

- [ ] Run the complete Android quick-recovery V2 matrix on attached hardware.
- [ ] Complete a controlled same-condition USB/WiFi matrix.
- [ ] Recheck a Legacy OpenDisplay iOS/TestFlight runtime.
- [ ] Complete a run with two Android devices.
- [ ] Complete the planned 30-minute and 2-hour endurance runs.
- [ ] Repeat disconnect/reconnect timing and stale-connection callback stress on attached receivers.

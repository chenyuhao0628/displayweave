[English](https://github.com/chenyuhao0628/displayweave/blob/main/docs/release-notes-v0.2.0-preview.4.md) | [简体中文](https://github.com/chenyuhao0628/displayweave/blob/main/docs/release-notes-v0.2.0-preview.4.zh-CN.md)

# DisplayWeave `v0.2.0-preview.4` release notes

[GitHub prerelease](https://github.com/chenyuhao0628/displayweave/releases/tag/v0.2.0-preview.4) · [Release workflow](https://github.com/chenyuhao0628/displayweave/actions/runs/29347755688)

## Android latency and recovery controls

- Pre-encode capture drops no longer request an unnecessary IDR. Keyframe requests are coalesced and recorded with their reason.
- Android negotiates a bounded frame size before the Mac raises its legacy limit; invalid and oversize frames are rejected before allocation or decoder input.
- MediaCodec low-latency parameters are capability-gated with safe fallback. WiFi low-latency lock and Surface frame-rate hints have foreground, transport, Surface, and teardown lifecycle guards.
- Android drops are classified by congestion relevance. The Mac can apply a fast local bitrate decrease from queue age, send completion delay, or receiver evidence while retaining slow bounded recovery.

## Binary framing and measurement

- Android can independently advertise `binaryFrameHeaderV2`. The fixed network-order header carries session/config/frame identity, timestamps, payload length, codec, keyframe, and codec-config flags.
- Legacy OpenDisplay iOS and Android peers without the complete capability retain the existing JSON telemetry prefix plus Annex-B bytes.
- VideoToolbox output is tied to the ready connection generation; stale callbacks are discarded before framing.
- Android retains one transport array through the latest-frame slot and MediaCodec handoff, uses a single-pass NAL summary, and exposes allocation, reuse, pool-miss, and GC counters.
- Benchmark CSV/JSONL now records Android thermal status, power saver, battery temperature, battery level, and charging state. Missing platform readings remain unavailable rather than being replaced with zero.

## Build and update verification

The manually dispatched Release workflow built target commit `f300f88e84423f2a895d8b15dc3e514362e050bc` as Mac/Android build `5`. The workflow completed the Mac Release build, unsigned iOS compatibility build, signed Android Release build (`72 actionable tasks`, six Android self-test groups), APK signer verification, complete update-release verification, asset upload, and Pages feed deployment.

Before publication, the same target also passed all 22 standalone Swift tests, Android's 61-task Debug build, unsigned macOS/iOS Debug builds, the production site, 34 bilingual documentation pairs, and release-link validation.

The live [Sparkle feed](https://chenyuhao0628.github.io/displayweave/appcast.xml) and [Android update feed](https://chenyuhao0628.github.io/displayweave/android-update.json) were compared byte-for-byte with the signed Release assets after deployment.

## Distribution boundary

Mac remains ad-hoc signed and not notarized. Android is v2 signed by the pinned project certificate. The iOS artifact remains an unsigned arm64 re-signing input and is not automatically updated. The Release publishes seven immutable assets.

Controlled same-condition WiFi/USB performance, the full physical recovery V2 matrix, old TestFlight runtime compatibility, two-Android operation, and 30-minute/2-hour endurance remain pending. No latency reduction is claimed without those measurements.

## SHA-256

| Asset | SHA-256 |
| --- | --- |
| `DisplayWeave-macOS.dmg` | `a41539f180a2d1854307d70cfaa7328ec14348bdee7ce242e9e478df0f265c50` |
| `DisplayWeave-macOS.zip` | `28cc452cce5168db3813834f59fbb0ad290ac7a30cba83c5f79337bb5cf36a8a` |
| `DisplayWeave-Android.apk` | `11f3b7ce1e765aced8d1dfd255edfda83641f36db0863f37c6a948305e5c7820` |
| `DisplayWeave-Preview-0.1-iOS-unsigned-resigning-input.ipa` | `a43b7b99c861f9d4f60c85f0ce0bcc57e21c428fb106317df89a42fe8966d15a` |
| `appcast.xml` | `4eedf2ce46dc4908de8b8a414f8dd860d8a09042c2cdc9c206dc360428d37049` |
| `android-update.json` | `c225d438f89c615d167a3448016626205a20bb6d12190c58b48742283b33dceb` |

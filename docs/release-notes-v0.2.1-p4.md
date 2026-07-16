[English](https://github.com/chenyuhao0628/displayweave/blob/main/docs/release-notes-v0.2.1-p4.md) | [简体中文](https://github.com/chenyuhao0628/displayweave/blob/main/docs/release-notes-v0.2.1-p4.zh-CN.md)

# DisplayWeave `v0.2.1-p4` release notes

DisplayWeave 0.2.1-p4 fixes WiFi and Android USB reconnect failures that could leave the receiver stuck at “Configuring decoder”.

## Changes

- Requests a replacement keyframe whenever Android applies a stream configuration, including the fresh-decoder H.264/60 default-config case.
- Treats a successful VideoToolbox callback without a sample buffer as a dropped frame instead of a codec failure.
- Prevents false encoder fallback and reconnect storms caused by those empty successful callbacks.
- Adds deterministic Android and macOS regression coverage for both reconnect edge cases.

## Validation

- All 22 macOS standalone self-test suites pass.
- Android unit tests and the Debug APK build pass.
- The macOS Debug app builds successfully with Xcode.
- On a physical OnePlus Android device, an interrupted ADB USB forward is recreated and the stream returns to 57–58 rendered FPS.
- On the same device over WiFi, force-stopping and restarting the receiver creates a new session, passes through decoder configuration, and returns to 57–58 rendered FPS.
- Repeated adaptive stream reconfiguration reaches `decoderReady`, `waitingFirstFrame`, and `streaming` instead of remaining in decoder configuration.
- `git diff --check` passes.

The macOS app remains ad-hoc signed and is not notarized. Android is signed with the pinned DisplayWeave release certificate.

## SHA-256

- Android APK: `221dac7f6ee6e59edbf76a30c4f2a70f279ec82f4d588b5c6e24f9226b0279c4`
- macOS ZIP: `4e8e7d9bf8a72d447b4d3f9bad45df1739dbfbb7f02f114145d928e1269a9ff8`
- macOS DMG: `6013fc4c11459925591e1caec82b6702f2acd5c5a3df2ed3c0ead6a071aac8f0`
- iOS unsigned re-signing input: `10ff8351f8c553f6b06c18eed6c03b8c3fa350c5a916af24aae299901cfa5cf0`
- Sparkle appcast: `1b295cb241576eb2eca475c1494ea89e57027f8351e377f5636db6018f7870f8`
- Android update manifest: `1803ff3710db76afec2ff88f80151427c888c862d8e22f644bf869beada52f71`

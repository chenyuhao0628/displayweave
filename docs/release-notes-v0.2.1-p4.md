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

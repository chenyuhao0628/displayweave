[English](https://github.com/chenyuhao0628/displayweave/blob/main/docs/release-notes-v0.2.1-p5.md) | [简体中文](https://github.com/chenyuhao0628/displayweave/blob/main/docs/release-notes-v0.2.1-p5.zh-CN.md)

# DisplayWeave `v0.2.1-p5` release notes

DisplayWeave 0.2.1-p5 hardens Android decoding against malformed H.264 configuration data and removes cross-thread teardown races on both sides of a reconnect.

## Changes

- Rejects truncated, overflowing, or invalid H.264 SPS data with a controlled decoder recovery instead of terminating the Android decode worker.
- Guarantees that the Android latest-frame worker returns to an idle or rescheduled state after a runtime decoder error.
- Validates stream configuration before committing protocol state and records previously hidden control-message failures.
- Makes the Mac clock offset safely visible across threads and snapshots it before touch timestamp conversion.
- Serializes Mac capture, encoder, stream, and virtual-display teardown state during stop and rotation rebuilds.
- Uses one consistent keyframe classifier when prepending H.264/H.265 parameter sets.
- Adds deterministic regression coverage for malformed SPS input and decode-worker recovery.

## Validation

- All 22 macOS standalone self-test suites pass.
- Android unit tests and the Debug APK build pass.
- The macOS Debug app builds successfully with Xcode.
- `git diff --check` passes.

The macOS app remains ad-hoc signed and is not notarized. Android is signed with the pinned DisplayWeave release certificate. Physical WiFi and USB reconnect validation was not rerun for this patch.

## SHA-256

- Android APK: `283b27a593063047a810c2cf9de255f64e87f0e7eb50e79701488b7bcfb46f22`
- macOS ZIP: `331faad563cf81c3e9582246d7a1d283a6c388bdd3dc339d28e7454694dc2fc8`
- macOS DMG: `b6454ff3b62aeb4cb2d2af644424a3c9ae63061ce4ff10df4c3a071c9056d61a`
- iOS unsigned re-signing input: `2ca4b21359c30ea0d604e2d5a9747dc4aa315610fa86e8b131afe1ef03da26a0`
- Sparkle appcast: `3bc5becfd6d2e4c1e5321acc231e9b25cca5404592a40d0371b651f3308a12c9`
- Android update manifest: `61da584c4b78ff0e2f2eb8292a60fbc6a732bfa49bbd2f989c0aaee2c4f22d1b`

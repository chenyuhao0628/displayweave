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

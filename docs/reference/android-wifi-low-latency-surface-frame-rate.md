[English](android-wifi-low-latency-surface-frame-rate.md) | [简体中文](android-wifi-low-latency-surface-frame-rate.zh-CN.md)

# Android WiFi low latency and Surface frame rate

This document records PR 6 of the Android stability/latency work. It adds a bounded, power-aware WiFi low-latency lock lifecycle and completes the existing Surface frame-rate hint lifecycle without changing the transport protocol, bitrate, queue depth, codec, or Legacy iOS path.

## Purpose

The receiver previously had no `WIFI_MODE_FULL_LOW_LATENCY` lock. Its Surface already used the API 30 two-argument `setFrameRate`, whose platform implementation defaults to only-if-seamless, but the hint was not represented as a lifecycle: stop/background cleanup, explicit decoder-rebuild reapplication, and Benchmark evidence were missing.

## WiFi setting and lifecycle

Android **Settings & Help → WiFi Low Latency** provides Auto (default), On, and Off. Auto and On use the same safe eligibility rule in this version. The lock is requested only on API 29+ when all conditions are true:

```text
actual transport = WiFi
+ app foreground
+ Streaming reached
+ Surface valid
```

It is non-reference-counted, so repeated state/metrics events cannot stack acquisitions. USB/ADB transport, socket disconnect or streaming stop, app background, Surface destruction, setting Off, and Activity destruction release it. Runtime exceptions during acquire/release are contained and reported; they do not fail the connection. The manifest declares the platform-required `WAKE_LOCK` permission.

The Android framework can report that this app owns the lock, but public API 29 does not prove chipset-level activation. Therefore `wifiLowLatencyActive` means the app owns the lock while all application lifecycle conditions are true; it is not fabricated radio telemetry.

## Surface frame-rate lifecycle

The requested video FPS is mapped to the smallest supported display rate at or above it, falling below only when no higher mode exists. This avoids mapping 90 FPS down to 60 Hz on devices that expose 60/120/165 Hz modes. The window and Surface receive a hint with fixed-source compatibility. API 31+ explicitly passes `CHANGE_FRAME_RATE_ONLY_IF_SEAMLESS`; API 30 uses the two-argument overload, which has the same only-if-seamless default.

The hint is applied or reapplied for Surface creation/change, foreground resume, StreamConfig FPS change, decoder rebuild, and Streaming start. It is cleared with frame rate zero when streaming stops, the app backgrounds, the Surface is destroyed, or the Activity exits. No non-seamless switch is requested by default.

The UI and Benchmark distinguish requested video FPS, requested Surface FPS, actual Android display Hz, and rendered FPS.

## Runtime and Benchmark fields

Receiver stats and Mac CSV/JSONL record:

- `requestedSurfaceFrameRate`, existing `actualAndroidDisplayRefreshRate`, and `frameRateApplyResult`;
- `wifiLowLatencyMode`, `wifiLowLatencyRequested`, `wifiLowLatencyAcquired`, `wifiLowLatencyActive`, and `wifiLowLatencyReleaseReason`.

## Modified files

- Android Manifest, Activity lifecycle/settings/Surface integration, server listener/stats, and new WiFi/Surface lifecycle classes;
- Android failure-first lifecycle and protocol tests;
- Mac receiver-stats decoding and Benchmark CSV/JSONL schema/tests;
- Android and repository bilingual documentation.

## Tests

Deterministic tests cover Auto/On/Off defaults, API gating, WiFi eligibility, USB release, foreground/background release, duplicate-acquire prevention, destruction cleanup, Surface create/config/decoder/streaming/resume reapplication, idempotent clearing, stats JSON, and stable unique Benchmark columns.

## Build result

- Android `clean test assembleDebug`: passed, 61/61 tasks executed; all six self-test groups reported PASS and the Debug APK assembled successfully.
- Mac standalone tests: all 21 passed, including stable, unique CSV columns for the new WiFi/Surface fields.
- `xcodegen generate`: passed.
- macOS Debug build with signing disabled: `BUILD SUCCEEDED`.
- generic iOS Simulator Debug build with signing disabled: `BUILD SUCCEEDED`, preserving the Legacy iOS source path.
- Website production/SSR/prerender build: passed.
- Bilingual documentation check: passed, 29 linked pairs including PR 4, PR 5, and PR 6.
- Release-link check and `git diff --check`: passed.

## Before/after metrics

No same-condition WiFi Lock Off/On or Surface-hint A/B has been collected. This PR does not claim lower RTT or Frame Age. It creates bounded controls and records the evidence required for a valid comparison.

## Known risks

- The WiFi lock trades power and potentially throughput/roaming behavior for scheduling latency; Auto is therefore bounded to active WiFi streaming.
- Lock ownership does not prove that vendor firmware changed radio scheduling.
- A Surface hint is a request; the system may keep another refresh rate.
- Reapplication paths are deterministic in tests but still require real Activity/Surface/vendor validation.

## Pending physical validation

- Run same-device, same-codec/FPS/bitrate/scene WiFi Off/On comparisons and record RTT P50/P95, Frame Age P50/P95/P99, actual bitrate, rendered FPS, and drops;
- verify lock release on USB switch, disconnect, background, Surface loss, and app exit;
- verify Surface requested FPS, actual display Hz, rendered FPS, and apply result across 60/90/120 configurations;
- inspect visual stability and confirm no black-screen non-seamless transitions;
- repeat short WiFi and ADB USB recovery checks.

No Android device was attached during implementation, so no physical result is inferred from build success.

## Next step

Implemented in [PR 7's drop-reason policy](android-drop-reason-policy.md). PR 8 should add the bounded Mac-local fast decrease path.

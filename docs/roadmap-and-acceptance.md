# DisplayWeave Development And Acceptance Targets

## 中文摘要

本文使用四种状态：**已完成**、**已真机验证**、**实验性**、**计划中**。
Android WiFi、HEVC/H.264 回退、动态帧率、高刷新请求和性能统计已经完成；
OnePlus HEVC/120 WiFi 实测约 109-111 FPS。Android USB/ADB reverse、
iOS/iPadOS 120Hz、加密 WiFi 配对、正式签名和公证包仍未完成。任何 120Hz
宣传都必须同时给出真实 capture/encode/send/receive/decode/render 数据。

This document defines the current baseline and the evidence required for future
DisplayWeave claims. It replaces the earlier mixed implementation prompt and
roadmap with explicit status labels.

## Status Legend

- **Completed**: implemented and covered by build, policy, protocol, or runtime
  evidence in this repository.
- **Physically validated**: exercised on the named hardware and configuration.
- **Experimental**: implemented and usable for testing, but not yet validated
  broadly enough to describe as stable across devices.
- **Planned**: not implemented and must never be presented as a current feature.

## Current Verified Baseline

### Completed

- Android receiver with NSD discovery and local WiFi TCP transport.
- Optional capability fields in receiver `hello` messages.
- Backward-compatible `streamConfig` for codec, FPS, dimensions, bitrate, and
  transport selection.
- VideoToolbox HEVC/H.265 and H.264 encoding paths on macOS.
- Android `MediaCodec` HEVC/H.265 and H.264 decoding paths.
- Automatic H.264 fallback after HEVC setup, encode, or decode failure.
- Dynamic 30/60/90/120fps policy and Android high-refresh display requests.
- Latest-frame-oriented queueing, parameter-set/keyframe preservation, and
  keyframe recovery.
- Runtime capture, encode, send, receive, decode, render, queue, drop, bitrate,
  frame-size, and available latency/frame-age statistics.
- Mac settings for automatic/manual codec and FPS selection.
- Legacy receivers default to the H.264/60fps-compatible path.

### Physically Validated

Test configuration:

```text
Receiver: OnePlus OPD2413
Android SDK: 36
Transport: local WiFi
Requested mode: HEVC / 120fps
Android display mode: 120Hz reported active
```

Observed pipeline rates during the validated dynamic-content run:

```text
capture: 110 FPS
encode: 109 FPS
send: 110 FPS
receive: 111 FPS
decode: 111 FPS
render: 110 FPS
```

The same path was also physically validated with explicit H.264/60 fallback and
an Android 60Hz display-mode request.

### Experimental

- Android 90/120fps operation across devices and networks.
- Sustained high-refresh use beyond the current short physical validation.
- Broad decoder compatibility and thermal behavior.
- Simultaneous mixed Apple/Android receiver scenarios.

The measured OnePlus result is approximately 109-111 FPS end to end. It proves
that negotiation, HEVC transport, decode/render, and a 120Hz display request can
operate together on the tested setup. It does not prove stable 120 FPS, and it
must not be generalized to all hardware.

## Not Implemented

The following are planned, not current features:

- Android USB/ADB reverse transport.
- iOS/iPadOS 120Hz or high-refresh streaming.
- Encrypted WiFi pairing and authenticated transport.
- Signed and notarized DisplayWeave macOS release packages.
- A complete DisplayWeave App Store or Play Store distribution flow.
- Stable 120 rendered FPS across all supported hardware.
- Broadly validated mixed-platform multi-device operation.

## Acceptance Principles

1. A requested 120fps target is not evidence of 120 rendered FPS.
2. An active 120Hz physical display mode is not evidence of 120 unique frames.
3. Performance claims must use measured capture, encode, send, receive, decode,
   and render data from the same run.
4. Missing measurements must be reported as unavailable, never synthesized.
5. New capability and control fields must remain optional or versioned.
6. Legacy receivers must retain the H.264/60fps-compatible path.
7. HEVC failures must recover to H.264 without requiring a process restart.
8. Android USB must not be documented as supported until the ADB lifecycle,
   reconnect behavior, and real-device transport pass acceptance testing.
9. iOS/iPadOS high refresh requires an independent design and validation track.
10. GPL-3.0 obligations and OpenDisplay origin attribution must remain intact.
11. Concrete SideScreen code reuse requires the applicable MIT notice in
    `THIRD_PARTY_NOTICES.md`.

## Track 1: Reproducible Benchmarking

Create a debug-only benchmark mode with fixed profiles for 1920x1080,
2560x1600, and current receiver-native resolution at 60/90/120fps, using HEVC
and H.264 with fixed or automatic bitrate.

Export CSV or JSONL containing, where reliably available:

```text
timestamp
requestedFps
selectedFps
actualVirtualDisplayRefreshRate
contentProducedFps
captureFps
encodedFps
sentFps
receivedFps
decodedFps
renderedFps
codec
bitrate
averageFrameSize
encodeLatencyMs
decodeLatencyMs
endToEndLatencyMs
latestFrameAgeMs
queueDepthMac
queueDepthAndroid
droppedFramesMac
droppedFramesAndroid
androidDisplayRefreshRate
transport
macCPU
macMemory
androidTemperature
```

Use `notAvailable` for fields that cannot be measured honestly.

Internal benchmark labels:

```text
High Refresh Passed:
10-minute average rendered FPS >= 100

Near 120:
10-minute average rendered FPS >= 115
and no sustained queue growth

Stable 120:
10-minute average rendered FPS >= 117
most samples remain between 115 and 120
and latency/queues do not trend upward
```

These labels describe one tested configuration, not the whole product.

## Track 2: Stability And Recovery

Run 10-minute, 30-minute, and 2-hour sessions while monitoring FPS, frame age,
queues, drops, memory, CPU, temperature, black/garbled frames, codec failures,
and repeated keyframe requests.

Exercise at least:

- Android app close/reopen and background/foreground.
- Android lock/unlock and `Surface` recreation.
- Mac sleep/wake.
- WiFi interruption and recovery.
- HEVC initialization failure and HEVC-to-H.264 fallback.
- Fifty repeated connect/disconnect cycles.
- Portrait/landscape or display-profile changes where supported.

Acceptance requires recovery without an unrecoverable black screen, unbounded
queue growth, persistent latency growth, or process crash.

## Track 3: Android USB/ADB Reverse (Planned)

Implement only behind the existing `ReceiverTransport` boundary. Preserve the
WiFi path and reuse the same framed protocol, capability negotiation, codec
selection, metrics, and fallback behavior.

Acceptance requires:

- Explicit setup/teardown of `adb reverse`.
- Clear device selection when multiple Android devices are connected.
- Reconnect after cable removal, app restart, or ADB server restart.
- No documentation or UI claim of Android USB before real-device validation.

## Track 4: Encrypted WiFi Pairing (Planned)

Design peer authentication, key storage, trust reset, protocol negotiation, and
legacy behavior before implementation. Do not silently label plain TCP as
secure. Acceptance must include packet inspection demonstrating that video and
control payloads are not readable on the LAN.

## Track 5: Multi-Device Validation

Publish a matrix covering receiver platform, transport, codec, FPS, resolution,
session count, duration, reconnect behavior, cursor/input routing, and observed
resource use. Until that matrix exists, describe multi-device support as
inherited capability and ongoing DisplayWeave validation.

## Track 6: iOS/iPadOS High Refresh (Planned)

Treat iOS/iPadOS high refresh as a separate investigation. Document receiver
capabilities, H.264/HEVC constraints, render scheduling, ProMotion behavior,
thermal limits, and legacy compatibility before making implementation claims.

## Track 7: Release Readiness

Before publishing downloadable DisplayWeave packages:

- Establish macOS signing and notarization ownership.
- Verify entitlements, Sparkle/appcast signing, and release provenance.
- Update installation, Gatekeeper, privacy, and rollback documentation.
- Align iOS distribution metadata and screenshots with DisplayWeave branding.
- Verify all native icons at platform-required sizes.

Until then, the repository remains source-first.

## Required Verification For Documentation Claims

Use the relevant subset of:

```bash
./generate.sh

xcodebuild -project OpenSidecar.xcodeproj \
  -scheme OpenSidecarMac \
  -configuration Debug \
  -derivedDataPath build-run \
  -clonedSourcePackagesDirPath build-run/SourcePackages \
  build

cd AndroidReceiver
./gradlew clean
./gradlew assembleDebug
./gradlew test
```

Also run `git diff --check`, inspect generated artifacts, and record the actual
hardware/configuration for any new runtime performance claim.

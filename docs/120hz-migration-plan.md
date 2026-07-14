[English](120hz-migration-plan.md) | [简体中文](120hz-migration-plan.zh-CN.md)

# DisplayWeave Android High-Refresh Migration Record

## 中文摘要

核心迁移已经完成：Android 支持可选能力协商、`streamConfig`、HEVC 与
H.264 自动回退、动态 30/60/90/120fps、高刷新显示请求、低延迟队列和
运行时统计。OnePlus OPD2413 在 HEVC/120 WiFi 环境下实测约 109-111
FPS，Android 显示模式为 120Hz，但仍未达到稳定满 120 FPS。本文后续内容
保留迁移前审计和各阶段实现记录，不应把历史“未完成”描述当作当前状态。

> **Status:** The core migration described here is complete. This document
> preserves the original audit, phase history, implementation notes, and
> physical-device evidence. It is not a description of pending work.

DisplayWeave migrated the inherited fixed H.264/60fps WiFi path to optional
capability negotiation, dynamic 30/60/90/120fps selection, HEVC preference with
H.264 fallback, Android high-refresh display requests, bounded queueing, and
runtime performance statistics.

The completed path was physically validated on a OnePlus OPD2413 running
Android SDK 36. In HEVC/120 over WiFi, capture through render measured about
109-111 FPS while Android reported an active 120Hz mode. H.264/60 fallback was
also validated. High refresh remains experimental: this result is below
sustained 120 FPS and does not generalize to all hardware.

Still planned, not implemented: Android USB/ADB reverse, encrypted WiFi pairing,
iOS/iPadOS 120Hz, and signed/notarized DisplayWeave packages.

## Historical Phase-1 Audit

The sections below describe the pre-migration state and should be read as a
historical baseline unless a later implementation phase explicitly updates
them.

Reference repository audited: `tranvuongquocdat/SideScreen`, cloned locally to
`/private/tmp/SideScreen` for comparison.

## Current 60Hz Bottlenecks

The current project still treats 60fps as an implicit invariant across most of
the video path. Raising only the ScreenCaptureKit interval is not enough.

1. Virtual display is fixed at 60Hz.
   - `Mac/VirtualDisplay.swift` creates exactly one `CGVirtualDisplayMode` with
     `refreshRate: 60`.
   - The current log prints size only, not requested/actual refresh rate.
   - `Mac/CGVirtualDisplayPrivate.h` also comments that this private API may be
     capped at 60Hz, so fallback logging is important.

2. Capture is not driven by negotiated fps.
   - `Mac/MacSender.swift` sets `SCStreamConfiguration.minimumFrameInterval` to
     `CMTime(value: 1, timescale: 120)`.
   - The comment explains this is a workaround for a 60Hz virtual display, not
     a real end-to-end 120Hz configuration.
   - Capture FPS is counted in ping messages as `capFps`, but there is no
     requested-vs-actual fps diagnosis.

3. VideoToolbox is H.264-only and fixed to 60fps.
   - `Mac/MacSender.swift` creates `VTCompressionSession` with
     `kCMVideoCodecType_H264`.
   - It sets `kVTCompressionPropertyKey_ExpectedFrameRate` to `60`.
   - It sets `MaxKeyFrameIntervalDuration` to `60`, and uses no explicit frame
     duration when encoding (`duration: .invalid`).
   - Bitrate comes from `StreamQuality` only and does not scale with fps,
     codec, or resolution.

4. The wire protocol has no stream configuration.
   - Mac to receiver frames are length-prefixed Annex B payloads, with JSON
     control frames distinguished by payloads starting with `{`.
   - The Android receiver has no prior `streamConfig`, so it assumes H.264.
   - Codec, fps, width, height, bitrate, profile, and transport are not
     announced before decoder initialization.

5. Android hello lacks device capability fields.
   - `AndroidReceiver/.../LengthPrefixedProtocol.java` sends only:
     `type`, `pixelsWide`, `pixelsHigh`, `scale`, `device`, `id`.
   - `AndroidReceiver/.../DisplaySpec.java` stores only width, height, scale.
   - `Mac/MacSender.swift` `PhoneInfo` decodes only width, height, scale,
     device, and id. Older receiver compatibility is good, but there is no new
     capability path yet.

6. Android decoder is H.264-only and fixed to 60fps timestamps.
   - `AndroidReceiver/.../H264SurfaceDecoder.java` creates
     `MediaFormat.MIMETYPE_VIDEO_AVC`.
   - It parses H.264 SPS/PPS NAL types 7/8 and IDR type 5.
   - It increments `presentationUs += 16_666`, which forces a 60fps timeline.
   - It has frame-drop support through `KEY_ALLOW_FRAME_DROP`, but no dynamic
     codec/fps config and no HEVC VPS/SPS/PPS parsing.

7. Android rendering does not request a high refresh surface/window.
   - `AndroidReceiver/.../MainActivity.java` hosts a `SurfaceView`, but does
     not call `Surface.setFrameRate`, select a matching `Display.Mode`, or set
     `WindowManager.LayoutParams.preferredRefreshRate`.
   - `currentDisplaySpec()` reads screen size and density, not refresh rate or
     supported display modes.

8. Queueing is partially protected but not 120fps-aware.
   - Mac drops frames when `pendingSends > 3`, with comments tuned for 60fps.
   - Android drops if `MediaCodec.dequeueInputBuffer(0)` fails, but it does not
     maintain a latest-frame queue or distinguish keyframe/parameter-set
     frames beyond H.264 IDR detection.

## Hard-Coded FPS / Timing Locations

Current project locations found during audit:

- `Mac/VirtualDisplay.swift`
  - `CGVirtualDisplayMode(... refreshRate: 60)`
- `Mac/MacSender.swift`
  - SCK: `config.minimumFrameInterval = CMTime(value: 1, timescale: 120)`
  - Encoder: `codecType: kCMVideoCodecType_H264`
  - Encoder: `kVTCompressionPropertyKey_ExpectedFrameRate = 60`
  - Encoder: `MaxKeyFrameIntervalDuration = 60`
  - Cursor echo timer: 8ms / 120Hz. This can stay independent from video fps.
  - Backpressure comment assumes 60fps latency increments.
- `AndroidReceiver/.../H264SurfaceDecoder.java`
  - `MediaFormat.MIMETYPE_VIDEO_AVC`
  - `presentationUs += 16_666`
- `AndroidReceiver/.../LengthPrefixedProtocol.java`
  - hello omits `refreshRate`, `maxFps`, codec capabilities, SDK, model, and
    transport.
- `AndroidReceiver/.../MainActivity.java`
  - no `Surface.setFrameRate`, no preferred display mode, no refresh-rate
    fields in `DisplaySpec`.
- `iOS/PhoneReceiver.swift`
  - iOS receiver has its own H.264 path and metrics. It should be left
    compatible while Android-specific negotiation is added.

## SideScreen Reference Findings

SideScreen should be used as an implementation reference, not merged wholesale.
Important reference files:

- `/private/tmp/SideScreen/MacHost/Sources/VirtualDisplayManager.swift`
  - Accepts `refreshRate` as an argument.
  - Creates `CGVirtualDisplayMode(... refreshRate: Double(refreshRate))`.
  - Adds HiDPI anchor mode plus logical mode when HiDPI is enabled.

- `/private/tmp/SideScreen/MacHost/Sources/ScreenCapture.swift`
  - Stores `refreshRate`.
  - Calls `setupForVirtualDisplay(displayID, refreshRate:)`.
  - Sets `SCStreamConfiguration.minimumFrameInterval` to
    `CMTime(value: 1, timescale: CMTimeScale(fps))`.
  - Tracks fallback from `SCStream` to `CGDisplayStream`.
  - Limits pending encodes to avoid queueing latency.
  - Chooses HEVC full physical size or H.264-clamped size.

- `/private/tmp/SideScreen/MacHost/Sources/VideoEncoder.swift`
  - Accepts `StreamCodec` and `frameRate`.
  - Creates HEVC with `kCMVideoCodecType_HEVC` or H.264 with
    `kCMVideoCodecType_H264`.
  - Sets `ExpectedFrameRate` to `frameRate`.
  - Sets frame duration to `CMTime(value: 1, timescale: frameRate)`.
  - Prepends VPS/SPS/PPS for HEVC keyframes and SPS/PPS for H.264 keyframes.
  - Uses no B-frames and max frame delay zero for low latency.

- `/private/tmp/SideScreen/MacHost/Sources/StreamingServer.swift`
  - Has explicit codec negotiation concepts.
  - Newer clients can advertise frame metadata support.
  - AVC-only clients can force H.264 fallback before stream startup.
  - Sends display config before frames and waits for a sync frame before
    sending P-frames to a fresh client.
  - Logs fps, Mbps, average frame age, and dropped frames.

- `/private/tmp/SideScreen/MacHost/Sources/CodecLimits.swift`
  - Clamps H.264 dimensions for AVC decoder compatibility while HEVC keeps the
    original physical size.

- `/private/tmp/SideScreen/AndroidClient/app/src/main/java/com/sidescreen/app/CodecCapabilities.kt`
  - Probes usable hardware HEVC decoders.
  - Avoids software-only HEVC and known broken vendor HEVC implementations.

- `/private/tmp/SideScreen/AndroidClient/app/src/main/java/com/sidescreen/app/VideoDecoder.kt`
  - Generalizes decoder by MIME type.
  - Uses async `MediaCodec.Callback`.
  - Sets low-latency, priority, operating rate, and max-B-frame hints when
    supported.
  - Chooses a decoder by size/rate support and prefers hardware.
  - Requests keyframes when buffers are exhausted or decoder state is lost.
  - Uses real frame timestamps and drops stale output frames.

- `/private/tmp/SideScreen/scripts/setup-usb.sh`
  - Uses `adb reverse tcp:8888 tcp:8888` for USB low-latency transport.
  - This should remain a later OpenDisplay phase, not mixed into the first
    120Hz WiFi implementation.

SideScreen license note: the repository is MIT licensed. If any concrete code
is copied or adapted beyond high-level design ideas, add or update
`THIRD_PARTY_NOTICES.md` with SideScreen attribution.

## Key Differences

| Area | Historical pre-migration baseline | SideScreen reference | Migration direction |
| --- | --- | --- | --- |
| Device capability | Android hello has size/scale only | Codec capability negotiation exists | Extend hello JSON with optional fields and defaults |
| Virtual display fps | Hard-coded 60Hz | Refresh rate is an input | Add selected/requested fps to `VirtualDisplay` |
| Capture fps | SCK asks 120 as workaround | SCK fps follows setting | Use final fps after negotiation/fallback |
| Encoder codec | H.264 only | HEVC preferred, H.264 fallback | Add codec enum and fallback path |
| Encoder fps | ExpectedFrameRate fixed at 60 | ExpectedFrameRate and duration follow fps | Use final fps everywhere |
| Stream metadata | None before frames | Typed config/codec messages | Send JSON `streamConfig` before frames |
| Android decoder | H.264 Annex B only | MIME-configurable MediaCodec | Generalize decoder for AVC/HEVC |
| Android refresh | No high-refresh request | Uses display refresh for operating rate | Add surface/window refresh-rate requests |
| Queue policy | Basic socket/input drop | More explicit sync-frame/keyframe recovery | Keep latest-frame behavior and stats |
| Transport | WiFi + existing iOS USB/usbmux path | ADB reverse USB-first | Defer ADB reverse; add `transport` field now |

## Recommended File Changes

### Protocol and Settings

- `Mac/MacSender.swift`
  - Extend `PhoneInfo` with optional fields:
    `refreshRate`, `maxFps`, `supportedCodecs`, `preferredCodec`,
    `deviceModel`, `androidSdk`, `transport`.
  - Add defaults for old receivers: 60fps, H.264, current transport label.
  - Add `StreamCodec`, `FpsMode`, `CodecMode`, and `StreamSettings`, or put
    them in a new small Swift file if `MacSender.swift` becomes too large.
  - Compute final stream config once per connection/reconfigure:
    final fps, codec, resolution, bitrate, transport.
  - Send a JSON `streamConfig` before the first video frame and after every
    codec/fps reconfiguration.
  - Handle Android codec-failure JSON and rebuild with H.264.

- `AndroidReceiver/.../DisplaySpec.java`
  - Add fields for refresh rate, max fps, supported codecs, preferred codec,
    device model, SDK, and transport.
  - Keep constructor overload or static factory for old call sites.

- `AndroidReceiver/.../LengthPrefixedProtocol.java`
  - Expand `helloJson`.
  - Add `streamConfig` parser helpers if JSON parsing remains centralized.
  - Add codec-failure JSON helper for Android to Mac fallback.

### Mac Virtual Display

- `Mac/VirtualDisplay.swift`
  - Add `requestedRefreshRate` parameter.
  - Sanitize fps to supported buckets: 30, 60, 90, 120.
  - Create `CGVirtualDisplayMode` with requested fps.
  - After apply/select, inspect `CGDisplayCopyDisplayMode(displayID)` and log
    actual refresh rate if available.
  - On apply failure for 90/120, retry 60 before failing the connection.
  - Log requested refresh rate, actual refresh rate, resolution, scale, and
    fallback reason.

- `Mac/MacSender.swift`
  - Pass selected fps into `VirtualDisplay`.
  - If virtual display falls back to 60, propagate that final fps into capture
    and encoder rather than leaving downstream at 120.

### Mac Capture

- `Mac/MacSender.swift`
  - Change `startCapture(display:pixelsWide:pixelsHigh:)` to accept `fps`.
  - Set `minimumFrameInterval` to `CMTime(value: 1, timescale: fps)`.
  - Track requested capture fps and actual capture fps in ping/stats.
  - When requested fps is 90/120 but observed capture fps remains near 60, log
    likely causes: virtual display fallback, SCK limiting, WindowServer not
    producing frames, encoder blocking, or transport backpressure.

### Mac Encoder

- `Mac/MacSender.swift`
  - Split encoder setup and Annex B conversion so H.264 and HEVC are both
    supported.
  - Try HEVC when Android supports/prefers it; on VT creation or first encode
    failure, rebuild as H.264.
  - Set `ExpectedFrameRate` to final fps.
  - Pass `duration: CMTime(value: 1, timescale: fps)` to
    `VTCompressionSessionEncodeFrame`.
  - Use HEVC parameter set extraction for VPS/SPS/PPS and H.264 extraction for
    SPS/PPS.
  - Compute bitrate from resolution, codec, fps, quality mode, and transport.
  - Track encoded fps, encode latency, average frame size, bitrate, keyframe
    interval, and dropped-before-encode.

### Android Receiver and Decoder

- `AndroidReceiver/.../MainActivity.java`
  - Read true display refresh rate from `Display`, `WindowMetrics`, and display
    modes where available.
  - Build `DisplaySpec` with refresh-rate and codec capability fields.
  - Add `Surface.setFrameRate` on Android 11+ when stream fps is known.
  - Set `WindowManager.LayoutParams.preferredRefreshRate` on older supported
    APIs when useful.
  - Log requested fps, current display refresh, selected display mode, and
    whether surface frame-rate request was attempted.

- `AndroidReceiver/.../OpenDisplayServer.java`
  - Parse Mac `streamConfig` before video frames.
  - Initialize or reinitialize the decoder using codec/fps/size from config.
  - Default to old behavior, H.264 + 60fps, if no config is received.
  - Return codec failure JSON to Mac when HEVC is not available or fails.
  - Expand metrics with received/decoded/rendered fps, queue depth, codec,
    bitrate, and dropped frames.

- Rename or generalize `AndroidReceiver/.../H264SurfaceDecoder.java`.
  - Suggested name: `HardwareVideoDecoder`.
  - Accept MIME type (`video/hevc` or `video/avc`) and fps.
  - For H.264, keep current SPS/PPS parsing path as fallback.
  - For HEVC, parse VPS/SPS/PPS from Annex B or rely on stream config plus
    keyframe parameter sets.
  - Replace `presentationUs += 16_666` with dynamic fps-based increment or
    Mac-provided timestamps.
  - Add decoded/rendered fps and decode latency measurements.
  - Request keyframe on input-buffer exhaustion or decoder reset.

### Tests and Docs

- `AndroidReceiver/tests/java/.../ProtocolSelfTest.java`
  - Add tests for expanded hello JSON and default compatibility.
  - Add tests for `streamConfig` parsing and fallback defaults.

- `THIRD_PARTY_NOTICES.md`
  - Add SideScreen MIT attribution if any code is copied/adapted in later
    phases.

## Proposed Fallback Strategy

Fallback must be layered so one failed optimization does not kill streaming.

1. Old Android receiver or old hello fields missing:
   - Use H.264, 60fps, existing frame format.

2. Android says only 60Hz:
   - Use 60fps even if user selected Auto/120.

3. Virtual display creation at requested fps fails:
   - Retry 60Hz virtual display.
   - Use final virtual display fps for SCK and VT.

4. ScreenCaptureKit requested 90/120 but observed fps remains 60:
   - Keep streaming.
   - Log warning with requested and actual fps.
   - Do not force reconnect loops.

5. HEVC encoder creation or encode fails:
   - Rebuild encoder as H.264.
   - Send new `streamConfig`.

6. Android HEVC decoder missing or init fails:
   - Android sends codec failure.
   - Mac switches to H.264 and resends config/keyframe.

7. Network or decoder queue backs up:
   - Drop old non-keyframes.
   - Force a keyframe when reference state may be broken.
   - Preserve parameter-set/keyframe frames.

## Risks

- `CGVirtualDisplay` is private API and may ignore or reject 90/120Hz modes on
  some macOS versions/hardware.
- SCK emits frames on content changes; a static desktop can make apparent fps
  lower unless a test pattern is used.
- HEVC hardware support varies. Some Android devices advertise HEVC but have
  slow software decoders or broken vendor decoders.
- 2560x1600 at 120fps can exceed WiFi throughput or Android decode/compose
  budget, even with HEVC.
- Changing frame format without strict compatibility can break iOS receiver or
  old Android receiver. Prefer additive JSON config first.
- H.264 high resolutions may exceed common AVC decoder limits; clamp if needed.
- Parameter-set handling differs between H.264 and HEVC. Incorrect VPS/SPS/PPS
  handling will produce black screen or decoder errors.

## Test Plan

Build and unit checks:

- macOS build:
  `xcodebuild -project OpenSidecar.xcodeproj -scheme OpenSidecarMac -configuration Debug -derivedDataPath build-run -clonedSourcePackagesDirPath build-run/SourcePackages build`
- Android build:
  `cd AndroidReceiver && ./gradlew clean && ./gradlew assembleDebug`
- Android protocol tests:
  `cd AndroidReceiver && ./gradlew test`

Compatibility tests:

- Old protocol fallback: run Android receiver without new fields, confirm Mac
  selects H.264/60fps and connects.
- H.264/60fps explicit: force settings to 60/H.264 and confirm existing path
  still renders.
- HEVC unavailable: simulate or use AVC-only device; confirm Android reports no
  HEVC and Mac falls back to H.264.
- 60Hz Android device: confirm hello reports max 60 and Mac does not force 120.
- 120Hz Android device: confirm hello reports 120 and Mac requests 120.

Runtime validation:

- Enable animated test pattern so SCK has continuous frame changes.
- Confirm logs show:
  - requested fps
  - actual virtual display refresh rate
  - capture fps
  - encoded fps
  - sent fps
  - received fps
  - decoded/rendered fps
  - codec and bitrate
  - queue depths and dropped frames
  - Android display refresh rate
- Treat the path as truly 120Hz only when capture, encoded, sent, received,
  decoded, and rendered fps are all close to 120.

## Suggested Phase Order

1. Add capability fields to Android hello and Mac parsing with compatibility
   defaults.
2. Add stream config JSON, still using H.264/60fps.
3. Make fps dynamic through virtual display, capture, encoder duration, and
   Android PTS while keeping H.264.
4. Add Android high-refresh surface/window requests.
5. Add HEVC encode/decode with H.264 fallback.
6. Add expanded stats and queue policy.
7. Add UI/settings controls.
8. Add USB/ADB reverse as a separate transport phase.

## Phase 2 Progress

Implemented so far:

- Android hello now includes optional capability fields:
  `refreshRate`, `maxFps`, `supportedCodecs`, `preferredCodec`,
  `deviceModel`, `androidSdk`, and `transport`.
- Android `DisplaySpec` keeps the old constructor as an H.264/60fps/WiFi
  compatibility default.
- Android `MainActivity` reads current display refresh rate, scans supported
  display modes for max fps, detects codec capability, and reports WiFi as the
  current transport.
- Android added `CodecCapabilities` to prefer usable hardware HEVC when
  present and otherwise fall back to H.264.
- Mac `PhoneInfo` parses the new optional fields while defaulting old receivers
  to H.264/60fps.
- `PhoneInfo` now lives in `Mac/DeviceCapabilities.swift`, so old and modern
  hello payloads can be tested without bringing up ScreenCaptureKit.
- Mac connection logs now print reported device model, refresh rate, max fps,
  codec list, preferred codec, SDK, and transport.

Verification:

- macOS `OpenSidecarMac` Debug build passed with `xcodebuild`.
- Android protocol test coverage was added for the new hello JSON fields.
- `DeviceCapabilitiesSelfTest` directly decodes an old hello with all new
  fields absent and verifies H.264/60fps fallback; it also covers a modern
  HEVC/120fps hello and unsupported preferred-codec fallback.
- AndroidReceiver is now a standard Gradle Wrapper project. `./gradlew clean`,
  `./gradlew assembleDebug`, and `./gradlew test` pass locally; the debug APK is
  generated at `AndroidReceiver/app/build/outputs/apk/debug/app-debug.apk`.

Status after later phases:

- Virtual display refresh rate was completed in phase 3.
- ScreenCaptureKit dynamic frame interval was completed in phase 4.
- VideoToolbox dynamic fps/HEVC architecture was completed in phase 5.
- Stream config and Android dynamic H.264 PTS were completed in phase 6.
- Android HEVC MediaCodec setup and high-refresh surface requests were added
  in phases 7 and 8.

## Phase 3 Progress

Implemented so far:

- Added `Mac/RefreshRatePolicy.swift` for 30/60/90/120 fps bucketing,
  user/device fps selection, and virtual-display fallback order.
- Added `MacTests/RefreshRatePolicySelfTest.swift` to cover fps bucketing,
  Auto/user-limited selection, and 90/120 -> 60 fallback ordering.
- `VirtualDisplay` now accepts `requestedRefreshRate` instead of hard-coding
  `refreshRate: 60`.
- `VirtualDisplay` attempts the requested refresh rate first and retries 60Hz
  if the private API rejects the requested mode.
- `VirtualDisplay` records and logs `requestedRefreshRate`,
  `actualRefreshRate`, selected resolution, scale, and fallback reason.
- `MacSender` now chooses the requested virtual display refresh rate from the
  Android-reported `maxFps` and an optional Mac user override:
  `defaults write app.displayweave.mac.debug fps 90` or `120`.

Verification:

- `swiftc -module-cache-path /private/tmp/opendisplay-swift-module-cache Mac/RefreshRatePolicy.swift MacTests/RefreshRatePolicySelfTest.swift -o /private/tmp/RefreshRatePolicySelfTest && /private/tmp/RefreshRatePolicySelfTest`
  passed.
- macOS `OpenSidecarMac` Debug build passed with `xcodebuild`.

Status after later phases:

- ScreenCaptureKit dynamic capture fps was completed in phase 4.
- VideoToolbox dynamic fps/HEVC architecture was completed in phase 5.
- Android stream config, dynamic PTS, HEVC decode setup, and high-refresh
  surface requests were added in phases 6 through 8.

## Phase 4 Progress

Implemented so far:

- `RefreshRatePolicy` now exposes `captureIntervalTimescale(fps:)`, tested for
  30/60/90/120.
- `MacSender.startCapture(...)` now accepts final capture fps and virtual
  display refresh rate.
- `SCStreamConfiguration.minimumFrameInterval` is now
  `CMTime(value: 1, timescale: finalFps)` instead of the old fixed 1/120
  workaround.
- Extend mode uses the virtual display's actual refresh rate after fallback.
- Mirror mode uses the optional Mac fps override when present, otherwise 60fps.
- Mac ping/stats JSON now includes `requestedFps` and
  `actualVirtualDisplayRefreshRate` alongside `capFps`.
- Mac logs a throttled warning when requested capture fps is 90/120 but actual
  capture fps is materially lower, including likely causes:
  virtual-display refresh, ScreenCaptureKit limiting, WindowServer not
  producing high-refresh frames, encoder blocking, or transport backpressure.

Verification:

- `RefreshRatePolicySelfTest` passed.
- macOS `OpenSidecarMac` Debug build passed with `xcodebuild`.

Still intentionally unchanged after phase 4:

- VideoToolbox dynamic fps/HEVC was still pending until phase 5.
- Android codec/fps stream config and HEVC decode were still pending until
  phases 6 and 7.

## Phase 5 Progress

Implemented so far:

- Added `Mac/StreamEncodingPolicy.swift` for codec selection, dynamic bitrate,
  one-second keyframe interval, and fps-based frame duration.
- Added `MacTests/StreamEncodingPolicySelfTest.swift` for codec negotiation,
  requested bitrate ranges, keyframe interval, and frame duration.
- `MacSender` now configures VideoToolbox with the selected fps instead of a
  fixed 60fps `ExpectedFrameRate`.
- VideoToolbox bitrate, `DataRateLimits`, keyframe interval, and frame duration
  now scale with resolution, fps, and codec.
- The Mac encoder can create HEVC or H.264 sessions. If HEVC creation fails,
  it falls back before startup; if HEVC encode fails mid-stream, it invalidates
  the HEVC session, rebuilds H.264, re-sends `streamConfig`, and forces a
  keyframe.
- Annex B conversion now prepends H.264 SPS/PPS or HEVC VPS/SPS/PPS parameter
  sets on keyframes.
- Encode telemetry now logs `encodedFps`, `encodeLatencyMs`, codec, bitrate,
  keyframe interval, and average frame size.
- Automatic codec selection now follows Android capabilities and preferred
  codec, with `defaults write app.displayweave.mac.debug codec h264` or `hevc` as
  an override. HEVC failures still fall back to H.264.

Verification:

- `StreamEncodingPolicySelfTest` passed, including H.264 fallback stream-config
  JSON coverage.
- `RefreshRatePolicySelfTest` passed.
- macOS `OpenSidecarMac` Debug build passed with `xcodebuild`.

Remaining after phase 5:

- Android HEVC decoding was completed in phase 7.
- Android high-refresh `Surface` / `Window` requests were completed in phase 8.
- USB/ADB reverse remains a future transport phase.

## Phase 6 Progress

Implemented so far:

- Added a stream config control message before video frames:
  `type`, `codec`, `fps`, `width`, `height`, `bitrate`, `profile`, and
  `transport`.
- Added Android protocol helpers and self-test coverage for the stream config
  JSON shape.
- Android now consumes `streamConfig` before decoder initialization while
  preserving old behavior when no config is received: H.264 + 60fps.
- Android H.264 decoder now increments presentation timestamps as
  `1_000_000 / fps` instead of the old fixed `16_666us`.
- Android reports `codecFailure` when decoder initialization fails, including
  HEVC devices that advertise support but cannot configure the stream.
- Mac handles Android `codecFailure` for HEVC by rebuilding the encoder as
  H.264, re-sending stream config, and forcing a keyframe.
- Android surfaces HEVC decoder failures to the user with
  `HEVC 不可用，已请求回退 H.264` before requesting Mac fallback.

Verification:

- `StreamEncodingPolicySelfTest` passed.
- macOS `OpenSidecarMac` Debug build passed with `xcodebuild`.
- AndroidReceiver Gradle Wrapper `./gradlew test` passed, including codec
  fallback status coverage.

Remaining after phase 6:

- Full Android HEVC MediaCodec initialization was added in phase 7.
- Android high-refresh surface selection was added in phase 8.

## Phase 7 Progress

Implemented so far:

- Added `AndroidReceiver/app/src/main/java/app/opendisplay/android/VideoStreamConfig.java`
  to normalize codec, MIME type, fps bucket, bitrate, and NAL unit types.
- Generalized the Android decoder to initialize either
  `MediaFormat.MIMETYPE_VIDEO_AVC` or `MediaFormat.MIMETYPE_VIDEO_HEVC` from
  `streamConfig`.
- H.264 still parses SPS dimensions as before; HEVC uses the explicit
  stream-config width/height and waits for VPS/SPS/PPS parameter sets before
  configuring MediaCodec.
- HEVC keyframes and parameter sets use HEVC NAL type parsing; H.264 keeps the
  existing AVC NAL type parsing.
- Presentation timestamps now advance by `1_000_000 / fps` for both codecs.
- Decoder initialization failure sends `codecFailure` back to Mac so the Mac
  can rebuild H.264 and re-send stream config.
- Android decoder output and Surface render completion are now separate
  callbacks: MediaCodec output increments `decodedFps`, while
  `OnFrameRenderedListener` increments `renderedFps`.
- Mac default codec selection now follows Android capability negotiation again:
  HEVC is selected when Android reports/prefers HEVC, unless overridden by
  `defaults write app.displayweave.mac.debug codec h264`.

Verification:

- Added `VideoStreamPolicySelfTest` for codec/MIME/NAL/fps policy.
- Java source compile and `VideoStreamPolicySelfTest` passed with
  `javac -cp .../android-36.1/android.jar`.

## Phase 8 Progress

Implemented so far:

- Added `AndroidReceiver/app/src/main/java/app/opendisplay/android/RefreshRateController.java`
  to select the smallest supported display refresh rate at or above the requested fps.
- `OpenDisplayServer` now forwards stream config to `MainActivity`.
- `MainActivity` requests the selected refresh rate through
  `WindowManager.LayoutParams.preferredRefreshRate`.
- On Android 11+ (`Build.VERSION.SDK_INT >= 30`), `MainActivity` also calls
  `Surface.setFrameRate(..., FRAME_RATE_COMPATIBILITY_FIXED_SOURCE)`.
- Android logs `requestedFps`, current display refresh rate, selected refresh
  rate, and surface frame-rate result. The status overlay now includes codec,
  requested fps, decoded fps, rendered fps, and selected screen Hz when metrics
  are enabled.

Verification:

- Added `VideoStreamPolicySelfTest` coverage for refresh-rate selection.
- Java source compile and `VideoStreamPolicySelfTest` passed with
  `javac -cp .../android-36.1/android.jar`.

## Phase 9/10 Progress

Implemented so far:

- Mac already drops before encode when socket send backlog grows beyond the
  low-latency threshold and forces a keyframe to recover P-frame sync.
- Android decoder now reports dropped frames when no MediaCodec input buffer is
  available, a payload is too large for the input buffer, or decoder state is
  invalid.
- Android socket reading now uses a latest-frame decode handoff: the socket
  thread stores the newest frame and a single decoder worker consumes it, so
  ordinary queued frames are replaced instead of accumulating latency.
- The latest-frame handoff preserves queued keyframes and parameter-set frames:
  a normal P-frame will not overwrite a queued recovery/config frame.
- `OpenDisplayServer` now counts received frames, decoded frames, rendered
  frames, Android dropped frames, queue depth, current codec, requested fps,
  bitrate, and Android display refresh rate in each metrics window.
- `StreamMetrics` now carries received/decoded/rendered fps, requested fps,
  codec, bitrate, Android dropped frames, queue depth, Android display refresh
  rate, latest-frame age, end-to-end latency, decode latency, Mac
  virtual-display refresh rate, encoded fps, sent fps, average frame size,
  encode latency, Mac queue depth, Mac dropped-before-encode count, and
  transport while preserving the previous constructor for compatibility.
- Android status overlay now distinguishes received fps (`收`), decoded fps
  (`解`), rendered fps (`渲`), selected screen Hz, Android queue depth, Android
  drop count, capture fps (`捕`), encoded fps (`编`), sent fps (`发`),
  virtual-display Hz, bitrate, average frame size, Mac queue depth, Mac drop
  count, E2E latency, decode latency, and latest-frame age.
- Mac per-frame telemetry is paired with the Android latest-frame handoff and
  carried through MediaCodec output callbacks, so rendered-frame metrics can
  average latency values over the same one-second window as fps counters.
- Mac ping now sends a structured `StreamDebugStats` payload over the existing
  ping control message. Android accepts both the new field names
  (`droppedFramesMac`, `queueDepthMac`) and the previous `drops`/`pending`
  names as fallback.
- Mac send-window accounting now resets the sent-frame counter each stats
  interval so `sentFps` remains a per-window value.

Verification:

- Added `VideoFrameClassifier` coverage to `VideoStreamPolicySelfTest`.
- Added `VideoFrameTelemetry` and latency-field coverage to
  `VideoStreamPolicySelfTest`.
- Added `StreamDebugStats` coverage to `StreamEncodingPolicySelfTest` and Mac
  stats-field coverage to `VideoStreamPolicySelfTest`.
- Added `decodedFps` coverage to `VideoStreamPolicySelfTest`.
- Java source compile, `VideoStreamPolicySelfTest`, and `ProtocolSelfTest`
  passed with `javac -cp .../android-36.1/android.jar`.
- Swift self-tests for refresh-rate, stream settings, and encoding/stats
  policy passed. macOS `OpenSidecarMac` Debug build passed with `xcodebuild`.

Still remaining:

- End-to-end latency and decode latency depend on Mac/Android clock-offset
  estimates from ping/pong. Until an offset is available, the overlay reports
  frame age and omits E2E/decode latency.
- The Android latest-frame queue is intentionally one-deep. A deeper
  priority-aware queue is not planned unless a device-specific decoder needs
  it.

## Phase 11 Progress

Implemented so far:

- Added `Mac/StreamSettings.swift` as the centralized Mac stream settings
  model.
- `StreamSettings` owns:
  - FPS mode: Auto / 60 / 90 / 120.
  - Codec mode: Auto / HEVC / H.264.
  - Quality mode: Low / Balanced / High / Gaming.
  - Transport mode, currently WiFi.
  - Debug Stats toggle.
- The Mac UI now exposes FPS, Codec, Quality, Transport, and Debug Stats in the
  existing settings form.
- `MacSender` now consumes a `StreamSettings` value instead of reading fps and
  codec directly from scattered `UserDefaults` keys.
- Legacy `defaults` keys for `fps` and `codec` are still migrated when loading
  settings, so existing local overrides do not silently disappear.
- Legacy quality values also migrate: `best` becomes `high`, and `fast`
  becomes `low`.
- Quality now controls both capture scale and the dynamic codec/fps bitrate:
  Gaming favors a 75% capture size with more bitrate than Balanced to limit
  queueing while retaining motion detail.
- Changing FPS, codec, quality, or debug stats restarts active sender sessions
  so the stream is rebuilt with a fresh virtual display/capture/encoder/config
  path.

Verification:

- Added `MacTests/StreamSettingsSelfTest.swift`.
- `StreamSettingsSelfTest` passed.
- macOS `OpenSidecarMac` Debug build passed with `xcodebuild`.

Android displays the negotiated codec/fps/transport and the full debug metric
chain in its optional status overlay; stream selection remains Mac-controlled.

## Phase 12 Progress

Implemented so far:

- Added `StreamTransportMode` to centralize the stream setting surface for
  transport selection.
- The Mac UI now shows the current transport mode as WiFi, with USB/ADB reverse
  documented as the next implementation target.
- Existing `SenderTransport` remains the concrete connection mechanism for
  current WiFi/USB sender paths; Android still advertises `transport: "wifi"`.
- Added Android `ReceiverTransport` as the framed-payload boundary and moved
  `ServerSocket`, client socket, reader, and serialized writer ownership into
  `WifiTcpReceiverTransport`.
- `OpenDisplayServer` now owns protocol parsing, decoder queueing, metrics, and
  NSD orchestration without directly reading or writing TCP sockets.
- A loopback self-test verifies bidirectional length-prefixed payloads through
  the WiFi transport implementation.

As required for this release, `UsbAdbReverseTransport` is not implemented and
remains a separate follow-up. The new receiver boundary is the integration
point for it, so adding ADB does not require changing stream negotiation,
decoder, queue, or metrics logic.

## Phase 13 Verification and Acceptance

Automated verification commands:

```bash
cd AndroidReceiver
./gradlew clean
./gradlew assembleDebug
./gradlew test

cd ..
swiftc Mac/RefreshRatePolicy.swift MacTests/RefreshRatePolicySelfTest.swift -o /tmp/RefreshRatePolicySelfTest
swiftc Mac/RefreshRatePolicy.swift Mac/StreamEncodingPolicy.swift Mac/StreamSettings.swift MacTests/StreamEncodingPolicySelfTest.swift -o /tmp/StreamEncodingPolicySelfTest
swiftc Mac/RefreshRatePolicy.swift Mac/StreamEncodingPolicy.swift Mac/StreamSettings.swift MacTests/StreamSettingsSelfTest.swift -o /tmp/StreamSettingsSelfTest
xcodebuild -project OpenSidecar.xcodeproj -scheme OpenSidecarMac -configuration Debug -derivedDataPath build-run -clonedSourcePackagesDirPath build-run/SourcePackages build
```

Runtime 60Hz test:

- Select FPS 60 and Codec H.264, connect over WiFi, and confirm `streamConfig`
  reports `h264`/`60` and the Android overlay shows stable receive/decode/render
  values without a growing queue.
- An old receiver hello with no capability fields must select H.264/60fps.

Runtime 120Hz test:

- On a 120Hz Android display, select Auto or 120 and Auto/HEVC, enable Debug
  Stats, and run the animated test pattern.
- Confirm hello reports `maxFps: 120`, stream config reports HEVC/120 (unless a
  logged hardware fallback occurs), and Android requests a matching display
  mode/surface frame rate.
- Treat 120Hz as achieved only when capture, encoded, sent, received, decoded,
  and rendered FPS all remain close to 120. A lower stage identifies the
  bottleneck directly in the overlay.

### Physical-device results (2026-07-10)

Test device: OnePlus OPD2413, Android SDK 36, connected over WiFi.

- The receiver hello reported 3040x1904, `refreshRate: 120`, `maxFps: 120`,
  `supportedCodecs: ["hevc", "h264"]`, and preferred HEVC.
- Auto/120 mode created a 120Hz virtual display, sent HEVC/120 at 40 Mbps,
  initialized the Android hardware HEVC decoder, and selected the Android
  120Hz physical mode. `dumpsys display` confirmed active mode and render rate
  of 120.00001Hz.
- A SwiftUI/AppKit animation produced only about 60 FPS even on the 120Hz
  virtual display. Replacing the debug-only generator with a 120fps `MTKView`
  removed that test-source limit and produced a sustained high-refresh chain:
  `capture 110`, `encode 109`, `send 110`, `receive 111`, `decode 111`, and
  `render 110 FPS` in the Android overlay.
- Therefore 120Hz capability/configuration negotiation and an approximately
  110 FPS end-to-end HEVC path are verified on this hardware. It remains below
  a sustained 120 FPS; the measured residual limit is at capture/content
  production rather than Android display mode selection or decoder queueing.
- Explicit H.264/60 fallback was also tested. The Mac created a 60Hz virtual
  display and sent H.264/60 at 15 Mbps; Android selected its 60Hz mode and
  reported approximately 58 FPS for receive/decode/render without a growing
  keyframe-request loop.
- The initial HEVC black-screen/keyframe loop exposed an Annex B parser defect:
  parameter-set lookup used AVC NAL type bits for HEVC. The receiver now parses
  HEVC VPS/SPS/PPS types 32/33/34 correctly, with a regression self-test.

The remaining acceptance gap is the final roughly 10 FPS needed for sustained
120 FPS on this Mac. The statistics correctly expose that limitation instead
of treating a requested 120Hz mode as proof of 120 rendered frames per second.

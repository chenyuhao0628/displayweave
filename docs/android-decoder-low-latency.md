[English](android-decoder-low-latency.md) | [简体中文](android-decoder-low-latency.zh-CN.md)

# Android MediaCodec low-latency selection

This document records PR 5 of the Android stability/latency work. It adds capability-aware MediaCodec selection and bounded low-latency fallback without changing the transport, queue depth, bitrate, legacy iOS protocol, or MediaCodec input model.

## Purpose

PR 2 reported the decoder chosen by `createDecoderByType` and whether it advertised `FEATURE_LowLatency`, but it never set `KEY_LOW_LATENCY`. A vendor rejection of that parameter would also have failed the whole codec path. PR 5 makes selection and fallback explicit while keeping a working decoder more important than one optional parameter.

## Setting

Android **Settings & Help → Decoder Low Latency** provides:

- **Auto** (default): prefer a hardware decoder that explicitly reports low-latency support and request the feature;
- **On**: make the same capability-gated request as an explicit user choice;
- **Off**: never set `KEY_LOW_LATENCY`.

Both Auto and On obey the safety rule that the key is set only on API 30+ and only when the selected decoder reports `FEATURE_LowLatency`. On does not force an unsupported parameter. Changing the setting rebuilds the receiver session once; the existing Mac reconnect grace remains finite.

## Decoder order and fallback

For the negotiated codec MIME, Android enumerates decoder candidates and orders them as follows:

```text
hardware decoder
  -> low-latency-capable hardware decoder first (Auto/On)
  -> other hardware decoder
  -> unknown acceleration
  -> software-only decoder
```

Known broken HEVC implementations already excluded from advertised HEVC support remain excluded. For each low-latency-capable candidate in Auto/On, the configure attempt order is:

```text
same decoder + KEY_LOW_LATENCY=1
  -> if configure/start fails: release it
  -> same decoder without KEY_LOW_LATENCY
  -> next decoder candidate
  -> existing HEVC-to-H.264 sender fallback if every HEVC candidate fails
```

Failed candidates and callback threads are released before the next attempt. Vendor `stop()`/`release()` failures are contained. MediaCodec work remains on the existing decoder worker; the serialized network event executor does not wait for codec teardown.

## Runtime evidence and Benchmark fields

`decoderReady`, receiver stats, and Mac CSV/JSONL Benchmark output record:

- requested `decoderLowLatencyMode`;
- actual `decoderName`;
- `hardwareAccelerated`, `softwareOnly`, and Vendor status;
- `lowLatencySupported` and `lowLatencyEnabled`;
- `decoderConfigureSuccess` and `decoderFallbackReason`.

A successful fallback can therefore report support=true, enabled=false, and a reason such as `lowLatencyConfigureFailed:CodecException`. Exhausting all candidates records configureSuccess=false before the existing codec-failure/H.264 fallback message is sent.

## Modified files

- Android decoder, runtime info, codec capability helpers, server, settings UI, receiver stats, and new low-latency mode/selection policy classes;
- Android failure-first policy/protocol tests;
- Mac receiver-stats decoding and Benchmark schema/tests;
- Android and repository bilingual documentation.

## Tests

Deterministic tests cover Auto/On/Off parsing, default Auto, hardware-first ordering, low-latency-capable ordering, same-decoder enabled/disabled attempt order, Off behavior, explicit failed-runtime metrics, extended `decoderReady` JSON, receiver-stats JSON, and stable Benchmark CSV/JSONL fields.

## Build result

- Android `clean test assembleDebug`: passed, 61/61 tasks executed; all six self-test groups reported PASS and the Debug APK assembled successfully.
- Mac standalone tests: all 21 passed, including decoder Benchmark decoding plus stable and unique CSV columns.
- `xcodegen generate`: passed.
- macOS Debug build with signing disabled: `BUILD SUCCEEDED`.
- generic iOS Simulator Debug build with signing disabled: `BUILD SUCCEEDED`, preserving the Legacy iOS source path.
- Website production/SSR/prerender build: passed.
- Bilingual documentation check: passed, 26 pairs.
- Release-link check and `git diff --check`: passed.

## Before/after metrics

No same-condition physical Off/On A/B has been collected. This PR does not claim lower decode latency or Frame Age. It provides the actual selected mode and decoder evidence required for that comparison.

## Known risks

- Vendor capability advertisement can be inaccurate; the without-low-latency retry is therefore mandatory.
- Auto and On intentionally have the same safe enablement rule in this version; On expresses user intent but does not bypass capability checks.
- Decoder selection and failure fallback require physical validation across real vendor codecs.
- The synchronous `dequeueInputBuffer(0)` input policy is unchanged and belongs to a later stage.

## Pending physical validation

- On the same Android device/codec/FPS/bitrate/scene, run Off and On separately;
- compare Rendered FPS, Frame Age P50/P95/P99, Decoder Drops, and Decoder Errors;
- verify the actual decoder name and low-latency flags in Benchmark output;
- exercise a device that rejects `KEY_LOW_LATENCY` and prove same-decoder fallback;
- repeat short WiFi and ADB USB recovery checks after changing the setting.

No Android device was attached during implementation, so no physical result is inferred from build success.

## Next step

PR 6 should implement Android WiFi low-latency lock lifecycle and finish the Surface frame-rate hint policy as a separate power/display change.

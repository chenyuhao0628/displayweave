[English](frame-size-negotiation.md) | [简体中文](frame-size-negotiation.zh-CN.md)

# Android frame-size negotiation and oversize safety

This document records PR 4 of the Android stability work. It raises the usable Android Protocol V2 frame ceiling without removing length validation, changing the legacy iOS wire path, or introducing frame chunking.

## Purpose

The previous Android reader rejected every length-prefixed payload above 1 MiB. A valid large IDR could therefore look like a generic network disconnect. PR 4 makes the limit explicit and negotiated, rejects invalid input before payload allocation, and exports enough measurements to distinguish actual frame growth from malformed input.

## Negotiation and limits

Android advertises the additional capability and value in `hello`:

```json
{
  "protocolVersion": 2,
  "capabilities": ["maxFrameBytes"],
  "maxFrameBytes": 8388608
}
```

The capability is additive to the existing complete Protocol V2 identity/progress capability set. The Mac uses it only for a fully negotiated Android V2 peer and echoes the bounded value in V2 `streamConfig`.

The active limits are:

| Path | Limit | Rule |
| --- | ---: | --- |
| Legacy length-prefix reader | 1 MiB | Unchanged |
| Android Protocol V2 default | 8 MiB | Enabled only by V2 `streamConfig` |
| Absolute parser ceiling | 16 MiB | Never bypassed |

Every Android connection starts at the 1 MiB legacy limit. The small `streamConfig` control payload is parsed first; a V2 configuration then raises that connection's reader limit to at most the receiver-advertised 8 MiB. A legacy configuration keeps 1 MiB. This update happens before the reader accepts the following video frame, so the first negotiated large keyframe is not exposed to an asynchronous configuration race.

The Mac checks an encoded V2 video payload against the negotiated value before writing its 4-byte prefix. If it is too large, the payload is not sent, the event is logged, and the existing finite reconnect policy is entered. A peer without `maxFrameBytes` remains on the unchanged legacy send path.

## Rejection behavior

Android validates the 4-byte big-endian length before allocating the payload buffer and distinguishes:

- `invalid_length`: zero or negative length;
- `oversize`: above the negotiated connection limit;
- `absolute_limit`: above 16 MiB.

The transport publishes the typed reason, byte count, limit, and connection generation, closes only the current connection, and relies on the existing bounded reconnect lifecycle. A stale connection's late rejection cannot update current receiver state. No unlimited length, retry loop, queue, or frame chunking was added.

## Metrics

Receiver stats and Mac CSV/JSONL Benchmark samples now include:

- `currentFrameBytes` and `maxFrameBytesObserved`;
- `currentKeyframeBytes` and `maxKeyframeBytesObserved`;
- `oversizeFrameCount` and `invalidFrameLengthCount`.

“Current keyframe” means the most recently accepted keyframe. Current values reset on a new connection; observed maxima and rejection totals remain cumulative for the running receiver process. Keyframes are classified from H.264 IDR NAL type 5 and HEVC IRAP NAL types 19/20 after the existing telemetry prefix is removed.

## Modified files

- Android protocol, WiFi transport, server, frame classifier, stats snapshot, and the new `FrameSizeMetrics` accumulator;
- Mac capability parsing, frame-size policy, V2 stream configuration, sender guard, and Benchmark schema;
- Android and Mac failure-first self-tests;
- this bilingual document and the documentation indexes.

## Tests

The focused tests cover legacy 1 MiB rejection, V2 payload acceptance above 1 MiB, exact 8 MiB acceptance, typed rejection above 8 MiB, the 16 MiB absolute ceiling, zero length, connection-generation-scoped rejection, capability parsing/clamping, V2 echo, legacy omission, keyframe classification, all six metrics, and stable Benchmark CSV/JSONL columns.

## Build result

Verification completed on 2026-07-14:

- Android `./gradlew --no-daemon clean test assembleDebug`: passed, 61 tasks and all six self-test groups;
- all 21 Mac standalone self-tests: passed;
- `xcodegen generate`: passed;
- macOS `OpenSidecarMac` Debug with code signing disabled: passed;
- `OpenSidecariOS` generic Simulator Debug with code signing disabled: passed;
- `pnpm build`, 26-pair bilingual documentation check, release-link check, and `git diff --check`: passed.

## Before/after metrics

No same-condition physical A/B data has been collected for PR 4. This change does not claim lower Frame Age, higher throughput, or fewer reconnects. The new fields make maximum frame and keyframe sizes measurable in the next physical run.

## Known risks

- The 8 MiB choice has deterministic boundary coverage but has not yet been validated against a controlled physical-device workload.
- The sender still produces one complete frame per length prefix; chunking remains deferred.
- Keyframe classification still performs an Annex-B scan and allocation work that belongs to the later buffer/NAL optimization stage.
- Legacy iOS runtime compatibility still requires a physical TestFlight receiver check; its protocol bytes were not changed here.

## Pending physical validation

- Capture maximum frame/keyframe sizes on Android WiFi and ADB USB at HEVC 60/120;
- deliberately exercise an oversized header on a device and confirm the typed log, finite reconnect, and no OOM;
- verify old OpenDisplay iOS video/input/ping/reconnect behavior;
- compare Frame Age P50/P95/P99 and keyframe peaks under the same scene and settings.

No Android device was attached during the final PR 4 verification, so these items remain explicitly pending rather than inferred from desktop tests.

## Next step

PR 5 should implement MediaCodec low-latency capability selection and fallback reporting without mixing in WiFi locking, Surface policy, or asynchronous MediaCodec input.

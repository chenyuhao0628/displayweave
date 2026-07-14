[English](android-drop-reason-policy.md) | [简体中文](android-drop-reason-policy.zh-CN.md)

# Android drop-reason and adaptive-bitrate policy

## Modified files

- Android receiver: reason model/tracker, protocol statistics, decoder and transport drop sites, and deterministic self-tests;
- Mac sender: receiver-stat decoding, Benchmark CSV/JSONL fields, adaptive-controller filtering, and standalone tests;
- documentation indexes, phase-zero status, and bilingual-document validation.

## Purpose

PR 7 replaces the ambiguous Android aggregate-drop signal with attributable window and lifetime counts. It also prevents lifecycle, stale-identity, malformed-input, transport-transition, and codec-reconfiguration drops from being interpreted as network congestion.

The aggregate `androidDroppedFrames` field remains for UI and older Mac builds. New Mac builds consume the additive fields below; this does not change framing or Legacy iOS behavior.

## Classification and evidence

The receiver recognizes these stable reason keys:

| Reason | Congestion input | Meaning |
| --- | --- | --- |
| `latestSlotReplaced` | Yes | a newer frame replaced the one-slot pending frame |
| `importantFrameProtected` | Yes | a non-important incoming frame was rejected to preserve a queued important frame |
| `decoderInputUnavailable` | Yes | MediaCodec had no immediate input buffer |
| `frameAgeExpired` | Yes | a future age policy discarded stale work |
| `decoderInputOversize` | No | decoder input capacity was smaller than the frame |
| `decoderException` | No | the decoder rejected work or entered an illegal state |
| `surfaceUnavailable` | No | no valid render Surface was available |
| `staleConnectionGeneration` | No | work belonged to an old connection generation |
| `staleSessionEpoch` | No | negotiated session identity was stale |
| `staleConfigVersion` | No | config identity or frame ordering was stale |
| `invalidFrameLength` | No | framing rejected an invalid or oversized length |
| `malformedAnnexB` | No | the video payload had no usable Annex-B NAL unit |
| `codecReconfigureDrop` | No | decoder/config replacement made the work ineligible |
| `transportReadFailure` | No | the current transport read failed |
| `transportWriteFailure` | No | the current transport write failed |

Every recorded event captures `reason`, `countWindow`, `countTotal`, `generation`, `sessionEpoch`, `configVersion`, `frameSequence`, `codec`, and `transport`. Receiver stats publish:

- `androidDropCountsWindow` and `androidDropCountsTotal`;
- `androidCongestionDrops` and `androidDropTotal`;
- `androidLastDrop` with the full identity context.

Old-generation callbacks remain isolated and cannot mutate the current decoder or connection state. Classification fields are additive JSON, so older senders ignore them safely.

## Adaptive-bitrate filtering

Auto bitrate no longer decreases because `androidDroppedFrames > 0`. It reacts to classified decoder-throughput pressure only after two consecutive receiver-stat windows contain `androidCongestionDrops`. A single classified window blocks a stable increase but does not immediately reduce bitrate.

Non-congestion Android drops neither trigger a decrease nor block the existing five-second stable recovery. Existing independent inputs remain active: Mac pending sends/drops, sustained Android queue depth, sent/encoded deficit, rising RTT, and rising Frame Age.

When connected to an older receiver that lacks classification fields, the Mac treats classified Android congestion as zero and continues using those existing independent signals. It does not infer congestion from the legacy aggregate count.

## Tests

- failure-first Android tests cover all 15 reason keys, congestion membership, window/lifetime counters, reset behavior, and complete last-event context;
- protocol tests cover nested reason maps and last-event JSON;
- adaptive-controller tests prove that unclassified/non-congestion drops are filtered, one congestion window is insufficient, two consecutive windows decrease, and filtered drops do not block stable recovery;
- Benchmark tests cover reason maps, congestion count, identity context, stable/unique CSV columns, and JSONL output.

## Build result

- Android `clean test assembleDebug`: passed, 61/61 tasks executed; all six self-test groups reported PASS and the Debug APK assembled successfully.
- Mac standalone tests: all 21 passed, including adaptive filtering and stable/unique Benchmark columns.
- `xcodegen generate`: passed.
- macOS Debug build with signing disabled: `BUILD SUCCEEDED`.
- generic iOS Simulator Debug build with signing disabled: `BUILD SUCCEEDED`, preserving the Legacy iOS path.
- Website production/SSR/prerender build: passed.
- Bilingual documentation check: passed, 30 linked pairs including PR 7.
- Release-link check and `git diff --check`: passed.

## Before/after metrics

No physical A/B data was collected. This PR changes attribution and controller input semantics; it does not claim lower Frame Age, fewer drops, or higher throughput. The new reason fields make future same-condition evidence separable by cause.

## Known risks

- Reason classification describes the software observation point; it cannot prove the hardware or network root cause.
- `latestSlotReplaced`, `importantFrameProtected`, and `decoderInputUnavailable` are throughput-pressure evidence only when sustained, hence the two-window filter.
- Older receivers provide no reason fields, so the controller deliberately relies on queue, RTT, Frame Age, and sender-side signals instead of guessing.
- The current non-blocking `dequeueInputBuffer(0)` behavior is unchanged; the 0/250/500 µs experiment remains separate work.

## Pending physical validation

- Capture same-condition WiFi and ADB USB samples and inspect aggregate drops versus reason-window sums;
- induce Surface loss, foreground/background transitions, transport replacement, and decoder reconfiguration and confirm they never produce an Android-drop bitrate decrease;
- induce sustained decoder pressure and verify a decrease occurs only after two classified windows;
- compare rendered FPS and Frame Age P50/P95/P99 before and after without changing queue depth, codec, FPS, bitrate bounds, or scene.

No Android device was attached during implementation, so build success is not physical-performance evidence.

## Next step

PR 8 is documented in [local fast congestion policy](mac-local-fast-congestion-decrease.md), and PR 9 is implemented in [Android binary framing/allocation](android-binary-frame-header-v2.md). The remaining step is physical compatibility/recovery evidence.

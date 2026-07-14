[English](android-stability-latency-audit.md) | [简体中文](android-stability-latency-audit.zh-CN.md)

# Android Stability and Latency Audit

Audit date: 2026-07-14

Branch and revision: `main` at `e6debbcad68a0bac1b0c286fbbbdf1ef2edd7c98`

Release reviewed: `v0.2.0-preview.2` (GitHub pre-release, published 2026-07-14)
Scope: the current working tree, including pre-existing uncommitted lifecycle and decoder-recovery edits.

This is the phase-zero audit for the Android connection-stability and latency work. It records observed behavior before the connection-generation implementation. It does not treat configured FPS, bitrate, or refresh-rate requests as measured results. No long-duration or multi-device validation is claimed.

> Implementation update (2026-07-14): PR 1 connection generation through PR 9 negotiated binary framing/allocation and the measurement-only thermal/power follow-up have since been implemented. The table below intentionally remains the phase-zero baseline; current behavior is documented in [frame-size negotiation](frame-size-negotiation.md), [decoder low-latency selection](android-decoder-low-latency.md), [WiFi low latency / Surface frame rate](android-wifi-low-latency-surface-frame-rate.md), [drop-reason policy](android-drop-reason-policy.md), [local fast congestion decrease](mac-local-fast-congestion-decrease.md), [binary framing/allocation](android-binary-frame-header-v2.md), and [thermal/power metrics](android-thermal-power-metrics.md). Physical recovery evidence remains pending in [Android quick recovery V2](android-quick-recovery-v2.md).

## Executive summary

The current receiver has a functional legacy length-prefixed TCP path, Android WiFi and ADB-forwarded USB share that path, TCP_NODELAY is enabled, ping/pong telemetry exists, Android uses a one-frame latest-wins queue, and the UI requests a matching display/surface refresh rate. Several measurement foundations are already present, including Frame Age percentiles, RTT/clock offset, pipeline FPS, queue depth, and aggregate drop counts.

The highest-priority defect is confirmed: `WifiTcpReceiverTransport.acceptLoop()` calls the blocking `readLoop()` inline. The server therefore cannot accept a replacement connection until the old reader exits. There is no connection generation, and transport callbacks do not carry connection identity. A late disconnect or writer error can consequently update global state, release the decoder, and stop streaming after a newer logical session should have taken over.

The next risks are the 1 MiB inbound frame ceiling, forced keyframes after pre-encode capture skips, lack of reasoned drop accounting, and the absence of negotiated session/config/frame identity. Decoder low-latency selection, WiFi low-latency locking, and local fast bitrate decrease are missing. These later items must remain separate from PR 1.

## Classification

- **Implemented**: present on the active path with direct code evidence.
- **Partially Implemented**: some required behavior exists, but the stated invariant or observability is incomplete.
- **Missing**: no active implementation was found.
- **Risk**: practical failure mode of the current behavior.
- **Recommended Priority**: `P0` blocks reliable takeover/recovery, `P1` is the next correctness/latency risk, `P2` is an optimization or measurement follow-up.

## Required audit answers

| # | Question | Classification and observed behavior | Risk | Recommended priority |
| --- | --- | --- | --- | --- |
| 1 | Can `WifiTcpReceiverTransport` continue `accept()` before the old `readLoop()` ends? | **Missing.** `acceptLoop()` accepts one socket and then calls `readLoop(accepted)` inline. The next `accept()` is reached only after that reader returns. | A half-open or blocked old TCP stream prevents immediate reconnect/takeover. | **P0 / PR 1** |
| 2 | Does a newly arrived connection immediately close the old connection? | **Partially Implemented.** `closeClient()` is called after `accept()`, but question 1 prevents a second socket from arriving at that code while the old reader is blocked. | The apparent replacement logic does not provide actual immediate takeover. | **P0 / PR 1** |
| 3 | Can a late old-connection disconnect overwrite new state? | **Risk confirmed.** `onDisconnected()` has no connection identity and `ReceiverConnectionCoordinator.onDisconnected()` always resets the queue, releases the decoder, clears connected state, and stops streaming. | A stale callback can tear down the current session. | **P0 / PR 1** |
| 4 | Is there a Connection Generation? | **Missing.** No receiver transport generation or generation-bearing callback exists. The Mac has an unrelated dial generation for its outbound attempts, which does not protect Android receiver callbacks. | Old readers, writers, and callbacks cannot be rejected deterministically. | **P0 / PR 1** |
| 5 | Is there a Session Epoch? | **Missing.** | Old-session frames cannot be identified after transport replacement. | **P1 / PR 2** |
| 6 | Is there a Config Version? | **Missing.** `streamConfig` contains codec/FPS/size/bitrate/transport only. | Frames from a previous decoder configuration are indistinguishable. | **P1 / PR 2** |
| 7 | Is there a Frame Sequence? | **Missing.** Frame telemetry contains capture and send timestamps but no sequence. | Loss, reordering, stale delivery, and time-to-first-frame cannot be attributed precisely. | **P1 / PR 2** |
| 8 | Is TCP_NODELAY enabled? | **Implemented.** Android calls `accepted.setTcpNoDelay(true)`; the Mac TCP parameters also set `noDelay = true`. | No known gap on the active TCP paths. | Maintain in **PR 1** and test socket configuration. |
| 9 | Is SO_KEEPALIVE enabled? | **Missing** on the Android accepted socket. | Kernel detection of dead peers is weaker; it cannot replace application liveness but is useful as a secondary signal. | **P0 / PR 1** |
| 10 | What is the application ping/pong timeout policy? | **Partially Implemented.** Both sides emit ping traffic every 2 seconds. The Mac updates `lastReceived` on incoming frames and reconnects after more than 5 seconds without any receiver payload. Android answers Mac pings and estimates clock offset, but it has no corresponding payload timeout/connection close policy. Retries are bounded on the Mac by its existing disconnect grace. | Android can retain a half-open connection until TCP fails; transport health and video health are not separated. | Connection identity in **PR 1**; richer health rules in later connection-health work. |
| 11 | Are socket connected, hello, stream config, decoder ready, first rendered frame, and streaming distinct states? | **Partially Implemented.** UI has a connected boolean and a streaming boolean. Streaming becomes true when decoder status text starts with `正在接收`, which is emitted on decoder configure/output-format events, not on the first rendered callback. There is no typed state/reason/timestamp model. | The UI can report streaming before a visible frame and cannot identify the recovery stage. | **P0 connection-state foundation in PR 1**; acknowledgements/readiness in **PR 2**. |
| 12 | Does a pre-encode drop force a keyframe? | **Yes; problematic.** `SendQueuePolicy.decision()` returns `forceKeyframe = true` whenever pending sends reach the budget, and `MacSender` sets `needsKeyframe` before the skipped capture frame ever enters VideoToolbox. | Unnecessary IDR frames and bandwidth spikes under local send pressure. | **P1 / PR 3** |
| 13 | Can keyframe requests be triggered repeatedly? | **Yes.** `needsKeyframe` is a boolean on Mac, which coalesces some requests before the next encode, but Android can send `kf` from missing SPS, config changes, decoder errors, reconnect/static recovery, and stall recovery without a recovery-cycle identifier or counters. | Repeated requests around decoder recovery can still create avoidable keyframe bursts and obscure cause. | **P1 / PR 3** |
| 14 | What is the maximum length-prefixed frame size? | **Implemented safety limit: 1 MiB inbound on Android.** `LengthPrefixedProtocol.MAX_FRAME_BYTES = 1 << 20`. The Mac sender writes a UInt32 length and has no matching outbound-size guard. | A valid large IDR can exceed Android's limit. | **P1 / PR 4** |
| 15 | What happens to an oversized frame? | **Partially Implemented safety.** Android rejects `length <= 0` or `> 1 MiB` before allocation by throwing `IOException`; the current transport reports a generic disconnect/error and closes the active socket. There are no oversize counters, negotiated limit, or distinct recovery reason. | A single large keyframe disconnects the whole stream and is hard to diagnose. | **P1 / PR 4** |
| 16 | Are `KEY_LOW_LATENCY` and `FEATURE_LowLatency` used? | **Missing.** | The selected decoder is not explicitly configured for its low-latency mode. | **P1 / PR 5** |
| 17 | Is the actual decoder name recorded? | **Missing.** Decoder creation uses `MediaCodec.createDecoderByType()` and does not publish `codec.getName()`. | Device-specific behavior cannot be correlated to the actual codec implementation. | **P1 / PR 5** |
| 18 | Are hardware and software decoders distinguished? | **Missing.** No `MediaCodecInfo` hardware/software/vendor capability report exists. | Slow software fallback can be mistaken for network congestion. | **P1 / PR 5** |
| 19 | Is `Surface.setFrameRate()` used? | **Implemented, with a gap.** `MainActivity.requestStreamRefreshRate()` sets the window preferred rate and calls `Surface.setFrameRate(target, FIXED_SOURCE)` on API 30+. It records requested/actual values in status/logs. It does not use the API 31 seamless-only change strategy overload and lifecycle reapplication/clearing is not modeled explicitly. | A refresh request may be less controlled than the proposed seamless-only policy. | **P2 / PR 6** |
| 20 | What does `dequeueInputBuffer(0)` do today? | **Implemented as non-blocking polling.** If no input buffer is immediately available, the frame is dropped and counted in the aggregate Android drop total. | Scheduler jitter becomes an unattributed decoder drop; no 0/250/500 us A/B exists. | **P2 experiment before async redesign** |
| 21 | Is an Android WiFi low-latency lock used? | **Missing.** | WiFi power scheduling can add latency, but benefit and power cost are unknown. | **P1 / PR 6**, capability/lifecycle guarded |
| 22 | Is there a frame buffer pool? | **Missing.** The path creates arrays/Data for framing, telemetry stripping, NAL extraction, and decoder CSD. | Allocation and GC can worsen 120 fps tail latency. | **P2 / PR 9 after measurement** |
| 23 | Are VPS/SPS/PPS/keyframe NALs scanned repeatedly per frame? | **Yes.** Queue importance classification scans NAL units; decoder startup calls `findNalUnit` separately for VPS, SPS, and PPS; keyframe flag detection scans again. `AnnexB.nalUnits()` copies each NAL into a new array. | Repeated O(frame size) work and allocation on the hot path. | **P2 / PR 9** |
| 24 | Are drops classified by reason? | **Missing.** Android and Mac expose aggregate drop counts; there is no required reason enum/counter set. | Recovery and adaptive bitrate cannot distinguish congestion, stale work, surface loss, decoder input pressure, or reconfiguration. | **P1 / PR 7** |
| 25 | Does Auto Bitrate treat every Android drop as congestion? | **Yes.** Any positive `androidDrops` returns the `android-drops` congestion reason; normal recovery also requires zero Android drops. | Non-congestion lifecycle/decoder drops lower bitrate incorrectly. | **P1 / PR 7** |
| 26 | Are thermal and power-saving metrics present? | **Missing.** | Thermal throttling and power saving can masquerade as decoder/network degradation. | **P2 measurement-only phase** |
| 27 | Is there fast local congestion loss cutting? | **Missing.** The pre-encode queue budget drops frames immediately, but bitrate evaluation is driven by receiver stats (roughly 1 second). There is no 100–250 ms decrease-only controller using pending-send age/completion delay. | Local queue growth can persist until the receiver control loop reacts. | **P1 / PR 8** |

## Additional phase-zero findings

### Connection ownership

- The transport stores one global `socket` and one global `output`; there is no immutable per-connection context.
- The writer executor is serial, but a queued write resolves the global output at execution time. It cannot state which connection requested the write, and writer failure is not generation-scoped.
- `isActive(Socket)` prevents an old reader's `finally` block from disconnecting a different socket only if replacement has already occurred. Because replacement cannot occur while the inline reader blocks, this check does not solve half-open takeover.
- `ReceiverConnectionCoordinator` is unconditional and has no stale-event result or structured transition.
- Video work queued on `decoderWorker` carries payload/telemetry only. It has no connection identity to reject work after takeover.

### Existing useful foundations to preserve

- Legacy 4-byte big-endian framing and JSON/Annex-B payloads.
- Legacy Android/iOS hello/control compatibility and `_opensidecar._tcp` discovery.
- Latest-frame-wins Android queue with important-frame protection.
- Mac send queue budgets of 1–3 frames; they must not be increased to hide latency.
- Existing finite reconnect/grace behavior, ADB-forward lifecycle, codec fallback, and static-screen keyframe replay.
- Frame Age P50/P95/P99, RTT/clock offset, capture/encode/send/receive/decode/render counters, and benchmark CSV/JSONL.
- Current refresh-rate request and actual-display-Hz reporting.

## Priority and PR boundaries

### PR 1 — implement now

1. Separate the acceptor from per-connection readers so `accept()` remains live.
2. Add monotonically increasing Android connection generation and immutable connection contexts.
3. Atomically replace current connection, then close the previous socket.
4. Scope connected/payload/disconnected/error/write events to a generation.
5. Permit only the current generation to update UI, reset/release decoder state, publish connection transitions, or write.
6. Enable TCP_NODELAY and SO_KEEPALIVE on every accepted socket.
7. Add a typed application connection-state model with reason, timestamp, and generation. PR 1 must not pretend that epoch/config acknowledgements already exist.
8. Add deterministic tests for late old-reader disconnect, late old-writer failure, rapid connections, blocked-old replacement, current-only disconnect, and current-only write.

### Explicitly deferred

Session epoch/config version/sequence and stream acknowledgements belong to PR 2; keyframe/drop policy to PR 3; max-frame negotiation to PR 4; MediaCodec low latency to PR 5; WiFi lock/surface refinements to PR 6; drop filtering to PR 7; fast local bitrate decrease to PR 8; protocol V2/buffer work to PR 9. No UDP/QUIC or asynchronous MediaCodec redesign should be folded into PR 1.

## Baseline evidence and validation limits

The repository contains short benchmark and recovery procedures, but no same-condition physical A/B data for the changes proposed here. Therefore:

- **Before/After Metrics:** not yet available; no latency reduction is claimed.
- **Known Risks:** current 1 MiB frame ceiling, aggregate drop attribution, forced IDR after pre-encode skip, and missing decoder/WiFi low-latency capability handling remain after PR 1.
- **Pending Physical Validation:** WiFi and ADB USB, HEVC 60/120, rapid reconnect, half-open replacement, Android background/foreground, USB removal/return, ADB restart, and legacy OpenDisplay iOS receiver compatibility.

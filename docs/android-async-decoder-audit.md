[English](android-async-decoder-audit.md) | [简体中文](android-async-decoder-audit.zh-CN.md)

# Android Async Decoder Audit

Baseline: `79cbf90fdc61bf296a222a10750b2fa7f0a2df1f`  
Physical validation: **Pending**

## Findings

### ADC-001 — P0 — stale rendered callback could consume current telemetry

- Affected file: `H264SurfaceDecoder.java`
- Reproduction: configure codec A, release it, configure codec B (whose presentation timestamps restart at zero), then deliver A's delayed frame-rendered callback.
- Root cause: normal `MediaCodec.Callback` methods checked codec object identity, but `OnFrameRenderedListener` did not. The shared map was keyed only by presentation timestamp.
- Impact: an old callback could remove B's telemetry and report it through the current listener, corrupting first-frame/render metrics and potentially advancing current-session state incorrectly.
- Fix: callback generation plus codec identity is now required on every callback, including frame-rendered events.
- Automated evidence: Android compilation, self-tests, `test`, and `assembleDebug` pass. A platform callback-injection test is still missing.
- Physical validation: Pending.
- Regression risk: low; stale callbacks are ignored and active callbacks retain existing behavior.

### ADC-002 — P0 — rendered telemetry was unbounded

- Reproduction: queue decoded output while render callbacks are absent or delayed (invalid/stalled Surface or vendor callback loss).
- Root cause: telemetry entries were removed only by frame-rendered callbacks and the map had no capacity or eviction policy.
- Impact: process-lifetime memory growth.
- Fix: insertion-ordered storage is capped at 512 entries; oldest entries are evicted, and peak/eviction counters are retained internally.
- Tests: build coverage passes; deterministic bounded-map tests remain to be added through an Android-independent helper.
- Physical validation: Pending.

### ADC-003 — P1 — input index ownership was not asserted

- Reproduction: vendor or lifecycle race emits the same available-input index twice before it is consumed.
- Root cause: `ArrayDeque` accepted duplicates and there was no ownership set.
- Impact: the same codec input index could be selected twice.
- Fix: an `availableInputBufferSet` now admits each index once; polling removes ownership and release/configure clears both structures.
- Tests: compile/self-tests pass; callback injection remains Pending.

### ADC-004 — P1 — runtime codec errors requested a keyframe but did not rebuild

- Affected files: `H264SurfaceDecoder.java`, `OpenDisplayServer.java`
- Root cause: `onError`, input queue exceptions, and output-release failures report a drop/keyframe request but do not consistently detach the failed codec, request a fresh config, or enforce bounded rebuild attempts.
- Impact: possible persistent black screen after a terminal codec error.
- Fix status: locally fixed. Terminal input/output/codec failures now enter one coalesced server recovery transition. HEVC reports codec failure so the sender rebuilds as H.264; H.264 requests a fresh V2 StreamConfig plus keyframe (Legacy requests a keyframe and reconfigures from its parameter sets).
- Automated evidence: Android self-tests and Debug build pass; real vendor codec failure injection is Pending.
- Physical validation: Pending.

### ADC-005 — P2 — empty input-buffer return semantics are weak

`returnInputBuffer()` queues a zero-byte input buffer using the current presentation timestamp after null/oversize input handling. This avoids losing an index but has not been proven safe on all vendor codecs. The safer recovery design is to transition to a bounded decoder reset rather than depend on empty submissions after exceptional input conditions.

## Pending-frame/reference-chain result

Both the transport latest slot and decoder pending slot protect important frames. When an unsubmitted non-keyframe is replaced by a non-keyframe, the implementation drops the replacement, enters keyframe-wait state, rejects subsequent dependent frames, and requests a keyframe. H.264 IDR (NAL 5) and HEVC IRAP types 16–23, including IDR and CRA, are now recognized and covered by deterministic tests.

## Callback identity table

| Event | Required identity | Current result |
| --- | --- | --- |
| Input/output/error/format callback | decoder generation + codec object | fixed |
| Frame-rendered callback | decoder generation + codec object | fixed |
| Listener delivery | connection generation + session epoch + config version | present in `GenerationDecoderListener` |
| First frame | current epoch + config + positive frame sequence | present for V2; Legacy intentionally uses zero identity |

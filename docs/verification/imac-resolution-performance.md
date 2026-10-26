[English](imac-resolution-performance.md) | [简体中文](imac-resolution-performance.zh-CN.md)

# iMac desktop scaling and encoder load

Date: 2026-10-26. Included in the v0.3.2 release package (21). Reviewed native source: `b01e132`; source PR #22 merged as `1bfa1ca`. See [release notes](../releases/v0.3.2.md) for publication evidence.

## Report and evidence

The reporter identifies both machines as approximately 2019 Intel iMacs. Receiver fullscreen state, exact CPU/GPU and OS versions remain unconfirmed. The supplied sender log contains a receiver announcement of 5120×2880 pixels at 2×, a 2560×1440-point virtual desktop, and a 4096×2304 H.264 stream targeting 60 FPS. The selected H.264 implementation reports hardware acceleration. The path reports wired Ethernet. Private logs and peer identifiers are not committed.

The final session has two windows with capture FPS at least 30. They report 31/44 captured FPS, 26.42/31.49 encoded FPS, 16/28 pre-encode/output drops, no pending sends, send completions around 0.12 ms and maximum encoder submission times around 25.85 ms. This is evidence of encoder-side pressure, not a measurement of sustained maximum network speed. Low FPS during a static desktop is expected. These two windows do not prove every interaction has the same bottleneck.

Two distinct scaling mechanisms were confirmed in code:

- The old fixed 3840×2160 preset creates only 1920×1080 logical points at 2×. Fitting that desktop on a 2560×1440-point receiving screen enlarges windows. Native already preserves announced receiver points; its generic label concealed that distinction.
- The receiving window aspect-fits the entire remote desktop. A small window scales it down even with the correct native desktop. Fullscreen is needed to compare desktop sizes directly; differently configured macOS scaling or physical pixel density can still produce differences.

The Apple decoder envelope remains 4096×2304 landscape / 2304×4096 portrait. A 5K desktop preset does not claim 5K video or 5K60 performance. HEVC is still hardware-gated and retains its negotiated H.264 fallback envelope.

## Implemented

- Added explicit iMac 4096×2304, 4480×2520 and 5120×2880 desktop presets. Existing preference raw values and geometry are preserved. Native is labeled **Match receiving screen** with announced logical dimensions. The session shows desktop points/backing pixels separately from encoded video dimensions.
- Added fullscreen/scaling guidance on both Macs. Stream quality affects video detail, not virtual desktop or window layout.
- Moved potentially blocking VideoToolbox submission onto a dedicated serial worker. At most two submissions are retained; existing asynchronous encode/send budgets still apply. Encoder creation, property changes and retirement share this worker. Generation checks continue to reject obsolete output and errors. Intermediate 40/50 FPS targets retain the two-frame pipeline.
- Added **Adapt Mac encoder load**, enabled by default and independently disableable. It is inactive for non-Mac receivers and bitrate benchmark mode. Three overloaded active windows are required; sparse animation, static desktops and network backlog are excluded. Resolution priority preserves raster and reduces capture FPS (down to 30 for a target of 30 or higher). Frame-rate priority reduces raster in bounded steps first, keeping virtual desktop geometry unchanged. Raster stays at least half its starting dimensions and at least 1280 pixels on its long edge unless originally smaller.
- Recovery needs five healthy active windows, projected submission headroom and at least 30 seconds. An unsuccessful recovery doubles the delay up to five minutes. No queue expansion or desktop rebuild is used for tuning. Settings and session status explain the active limit; diagnostics include average submission duration and encoder-pressure drops.
- Configuration updates retire cached pixels, pause new admissions, reject old-size buffers and protect replacement captures. An SCK update has a five-second deadline; timeout or an SCK/encoder configuration failure ends the affected session with a recovery action instead of leaving it silently frozen.

## Automated verification

The desktop preset regression failed before implementation. The intermediate-FPS cadence regression also failed before its budget fix. Pure load-policy tests cover the supplied pressure pattern, resolution/frame-rate preference, sparse/idle/network exclusions, recovery and bounds. The worker test blocks an encode deliberately and verifies control responsiveness, two-submission admission and retirement ordering. A current-source integration fixture executes the actual sender tuning method with controlled OS operations, covering codec fallback during an update, stale replacement, stop and SCK/encoder errors.

Verified locally: 63 Swift suites plus capture/load/admission production-method fixtures; universal arm64/x86_64 Mac Debug and iOS Simulator builds; Android tests/Debug/Lint; web build, 116 bilingual documentation pairs, release-link checks and whitespace; 12 distribution, 20 signing, 15 cleanup, 9 documentation-check and 5 packaging checks; 36 brand assets. The worker concurrency test also passed Thread Sanitizer. Native settings were visually inspected and the adaptation toggle verified off/on, restoring its original value.

With an independent built-in display online, real AppKit window/fullscreen/lifecycle and three cycles of 1×/2× virtual-display creation/removal passed. The standalone 4K probe on arm64/macOS 26.5.2 encoded 180/180 frames in each of its three isolated runs (one-slot baseline, two-slot baseline, new worker), with no skips or failures and approximately 60 FPS. The new worker measured about 13.99 ms median / 14.71 ms p95 encoding callback latency. Hardware query, frame-delay and speed-priority properties returned unsupported on this host. An earlier probe overlapped display lifecycle testing and its worker run dropped 84/180 frames; that contended run is retained as non-comparable evidence, not silently discarded. Neither synthetic run proves Intel or two-device performance.

Final source CI `40263716075` passed all three jobs. Actual Apple↔Java TLS, Mac/iOS Keychain and secure Android runtime checks passed. The secure iOS fixture passed on an isolated rerun; the first background-listener check failed and its log is retained. No iOS source changed. The load-update integration fixture covers the five-second timeout and late completion.

Local evidence is retained under ignored `artifacts/verification/imac-resolution-2026-10-26/`.

## Physical acceptance still required

On both iMacs, use the same macOS display scaling and fullscreen reception. Compare **Match receiving screen** and **iMac 5K**, checking window size and cursor alignment when dragging across displays. Check both directions on Ethernet, first with resolution priority, then frame-rate priority; record ten minutes of window dragging, scrolling and video, plus static periods. Confirm adaptation and recovery logs agree with visible behavior and that toggling the feature off retains the selected operating point. Reconnect and change desktop presets to verify resource cleanup. Report model/CPU/GPU, OS, app version, transport, desktop points, encoded raster/codec, target FPS and observed presentation separately.

Local synthetic video and an arm64 build cannot establish the Intel driver improvement or guarantee 4K/5K60. No such performance claim is made.

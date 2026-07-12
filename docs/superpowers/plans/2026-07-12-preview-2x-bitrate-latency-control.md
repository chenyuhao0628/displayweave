# Preview 2.x Bitrate and Latency Control Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add Auto, Manual, and experimental Benchmark bitrate modes, a fast-decrease/slow-increase adaptive controller, measured queue budgets, and transport-aware keyframe intervals without increasing default latency.

**Architecture:** Pure Swift policy types decide bitrate bounds, adaptive transitions, queue budget, and GOP interval. `MacSender` applies policy outputs on its existing serial queue and records every transition in benchmark samples/logs. UI persists user choices; existing codec fallback, reconnect keyframes, protocol compatibility, and per-session ownership remain unchanged.

**Tech Stack:** Swift 5.9/Foundation, VideoToolbox, SwiftUI, standalone `swiftc` self-tests, existing macOS Xcode target.

---

### Task 1: Bitrate mode policy and persistence

**Files:**
- Modify: `Mac/StreamSettings.swift`
- Modify: `Mac/StreamEncodingPolicy.swift`
- Modify: `MacTests/StreamSettingsSelfTest.swift`
- Modify: `MacTests/StreamEncodingPolicySelfTest.swift`

- [ ] Add failing tests for `BitrateMode.auto`, `.manual`, `.benchmark`; Manual choices 10/20/30/40/60/80/100/120/160 Mbps; Benchmark choices through 200 Mbps; persistence/default Auto; transport/codec bounds; invalid saved values fall back safely.
- [ ] Run tests and confirm RED on missing types.
- [ ] Implement `BitrateMode`, `ManualBitrate`, and `BitrateBounds` without changing the existing automatic formula. Auto initial bounds: HEVC WiFi 12–100, HEVC USB 20–160, H.264 WiFi 8–60, H.264 USB 10–100 Mbps. Manual clamps/disables outside the matching bound. Benchmark permits up to 200 Mbps and is never default.
- [ ] Run both self-tests GREEN and commit `feat: add bitrate modes and bounds`.

### Task 2: Adaptive bitrate controller

**Files:**
- Create: `Mac/AdaptiveBitrateController.swift`
- Create: `MacTests/AdaptiveBitrateControllerSelfTest.swift`

- [ ] Write failing deterministic tests using injected monotonic timestamps. Normal for five seconds (pending 0, no new drops, stable RTT/frame age, sent/encoded >=0.95) increases 7%; congestion (pending >=2, rising age, RTT jump, sent/encoded deficit, drops, sustained receiver queue) decreases 20% immediately; clamp to bounds; minimum hold, cooldown, and hysteresis prevent oscillation.
- [ ] Require every decision to contain previous bitrate, new bitrate, reason, and network state; Manual and Benchmark modes never adapt.
- [ ] Confirm RED, implement the pure state machine, run GREEN, and commit `feat: add adaptive bitrate controller`.

### Task 3: Sender bitrate integration and UI

**Files:**
- Modify: `Mac/MacSender.swift`
- Modify: `Mac/OpenSidecarMacApp.swift`
- Modify: `Mac/BenchmarkSample.swift`
- Modify: `MacTests/BenchmarkSampleSelfTest.swift`
- Modify: `project.yml`

- [ ] Add failing integration-policy tests for initial target selection, Manual target, Benchmark warning, adaptive decision application, and target/actual separation.
- [ ] Apply target changes on the sender queue with `VTSessionSetProperty(kVTCompressionPropertyKey_AverageBitRate)` and matching `DataRateLimits`; resend `streamConfig` after a change but do not rebuild the session unnecessarily.
- [ ] Feed local pending/sent/encoded/drops plus receiver RTT/frame-age/queue/drops into Auto once per receiver stats sample. Log structured transition reason/state and export previous/new bitrate/reason/network state.
- [ ] Add UI controls and the exact experimental warning: `Experimental`, `May increase latency`, `May cause queueing`, `For local benchmark only`. Distinguish Target Bitrate from Actual Bitrate.
- [ ] Run all Swift tests and xcodebuild GREEN; commit `feat: integrate bitrate controls`.

### Task 4: Low-latency queue budget policy

**Files:**
- Create: `Mac/SendQueuePolicy.swift`
- Create: `MacTests/SendQueuePolicySelfTest.swift`
- Modify: `Mac/MacSender.swift`

- [ ] Add failing tests mapping candidate budgets Gaming=1, Balanced=2, High=3 while keeping the policy explicitly experimental until A/B evidence exists. Test latest-frame drop at `pending >= budget` (not after exceeding it), drop count, and keyframe recovery request.
- [ ] Confirm TCP no-delay is requested for TCP/ADB paths where Network.framework exposes it; preserve Apple USB behavior.
- [ ] Replace the fixed queue constant with the policy result. Do not enqueue old frames and do not increase any default budget beyond three.
- [ ] Run GREEN/xcodebuild and commit `feat: apply bounded send queue policy`.

### Task 5: Transport-aware keyframe policy

**Files:**
- Create: `Mac/KeyframePolicy.swift`
- Create: `MacTests/KeyframePolicySelfTest.swift`
- Modify: `Mac/MacSender.swift`
- Modify: `Mac/BenchmarkSample.swift`

- [ ] Add failing tests for WiFi candidate GOP 1/2/3 seconds, USB 1/2 seconds, safe defaults WiFi=2 and USB=1, and exact frame interval by negotiated FPS.
- [ ] Preserve immediate forced keyframes for receiver `kf`, decoder codec failure/fallback, reconnect, stream-config rebuild, and transport replacement.
- [ ] Count keyframes, average/peak keyframe size, queue/frame-age spike correlation fields, and decoder recovery event where observable; unavailable values remain unavailable.
- [ ] Run GREEN/xcodebuild and commit `feat: tune transport keyframe policy`.

### Task 6: Bitrate, queue, and keyframe documentation

**Files:**
- Create: `docs/bitrate-modes.md`
- Create: `docs/bitrate-modes.zh-CN.md`
- Create: `docs/adaptive-bitrate.md`
- Create: `docs/adaptive-bitrate.zh-CN.md`
- Create: `docs/low-latency-queue-analysis.md`
- Create: `docs/low-latency-queue-analysis.zh-CN.md`
- Create: `docs/keyframe-strategy.md`
- Create: `docs/keyframe-strategy.zh-CN.md`
- Modify: `docs/README.md`
- Modify: `docs/README.zh-CN.md`
- Modify: `tools/check-bilingual-docs.sh`

- [ ] Document implemented policy separately from unexecuted physical A/B evidence. Candidate queue/GOP values are not declared optimal until measured.
- [ ] Explain mode bounds, adaptation signals/hold/cooldown/hysteresis, transition logs, failure/stop conditions, and exact Benchmark warning.
- [ ] Provide A/B tables with `Pending` rather than fabricated FPS/frame-age/keyframe values.
- [ ] Run documentation/site checks and commit `docs: document bitrate and latency controls`.

### Task 7: Full control-path verification

- [ ] Run every Mac standalone self-test, Android `clean test assembleDebug`, macOS Debug xcodebuild, website build, bilingual/release checks, and `git diff --check`.
- [ ] Verify Auto remains default; Benchmark remains Debug/experimental; old settings decode; H.264 fallback/reconnect keyframe tests still pass.
- [ ] Do not claim queue or GOP performance improvement without matched physical runs. Record the exact manual A/B steps and leave results pending when hardware automation is unavailable.

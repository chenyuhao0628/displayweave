[English](code-and-experience-audit-2026-10-26.md) | [简体中文](code-and-experience-audit-2026-10-26.zh-CN.md)

# Code and experience audit — 2026-10-26
**Historical snapshot:** OPEN statuses and unchanged-source statements below describe the audited baseline only. For repairs and current acceptance, see the [reliability and experience upgrade](reliability-experience-upgrade.md).


## Scope and evidence contract

Audited source: `01613ef9d118c16992156a8786c0f8d143dea73d`, local `main`, matching the live working remote `displayweave/main` when the initial review began. Latest batch: `39f97a5..01613ef`, PR #18 merged on 2026-10-23, 90 changed files. Implementation: `929eb93`; release preparation: `1c1c4e3` / `v0.3.0`. The follow-up expands to the current Mac, shared, iOS and Android source. The date follows the workspace's 2026-10-26 review context. The working tree was clean before recording this audit.

**The earlier review covered the latest batch, its callers and tests; it was not a complete module-by-module product acceptance.** This follow-up checks the functional groups in the matrix below, records deterministic reproductions and adds mobile runtime/UI evidence. It is still **not every source line, branch, device or user journey tested exhaustively**. No coverage percentage or physical-performance certification is claimed.

Production behavior is unchanged. All ten findings below remain **OPEN**. Only audit documentation and isolated reproduction tools were added. A passing reproduction means the recorded problem/constraint was observed, not that it was fixed. A successful build or regression suite does not contradict a missing interleaving test.

Evidence levels:

- **S:** source and caller/state review.
- **D:** deterministic execution of production policies, or explicitly identified method excerpts with OS operations stubbed.
- **R:** actual process/network/simulator execution of production code in an isolated fixture.
- **V:** captured UI inspected. Synthetic video is labeled; its timing is not physical device performance.
- **SKIP:** unperformed hardware, interaction or endurance verification. An empty issue cell is not a guarantee that the module has no defects.

## Findings retained from the latest batch

### A01 · P1 · A stale encode callback leaves forced-keyframe ownership latched — S/D

**Location:** `Mac/MacSender.swift:2280–2284`, `handleEncodedFrame`; `Mac/FrameDropPolicy.swift`, `KeyframeRequestTracker`; `helloReady` / connection replacement.

**Trigger:** a forced-keyframe encode is outstanding when the wire generation changes. The reconnect request is queued, then the old callback enters `.stale` and returns before completing the old `inFlightReason`. New calls to `consumePendingRequest()` return nil forever while that reason remains owned; normal callbacks have no forced reason to release it.

**Evidence:** [ReconnectKeyframeProbe.swift](../tools/audits/2026-10-26/ReconnectKeyframeProbe.swift) retains the exact old/current production callback prefixes and links the production tracker/counter. Baseline can force a reconnect keyframe; current source cannot. Another 100 new-generation callbacks and requests do not clear the latch. The baseline enum-exhaustiveness shim is unreachable and excluded from excerpt comparison.

**Impact:** explicit reconnect/decoder-recovery keyframe requests stop working until the session is replaced. Periodic keyframes can still restore a picture; this is **not proof of permanent black video**. Fix direction: generation-owned keyframe requests and retirement cleanup, preserving stale-callback isolation. Physical reconnect timing remains SKIP.

### A02 · P2 · Capture recovery treats old capture settings as the latest hello — S/D

**Location:** `Mac/MacSender.swift:900–938`, `recoverCapture`, especially 919–922; recovery completion at 961–964 and hello dispatch at 1691–1695.

**Trigger:** the receiver rotates or changes its Apple capability envelope while capture is interrupted (`stream == nil`). Ordinary hello-driven reconfiguration is skipped. The fast recovery path reuses active width/height/FPS/codec, yet returns the newest hello as though applied. The completion comparison then suppresses the required rebuild.

**Evidence:** [RecoveryConfigurationProbe.swift](../tools/audits/2026-10-26/RecoveryConfigurationProbe.swift), exact production recovery method with display/capture stubs and real hello comparison/coordinator: new hello `1080×1920`; reattached capture `1920×1080`; rebuilds `0`; completion reports a match.

**Impact:** stale orientation/size, and potentially stale decoder/FPS limits. Keep the actually applied configuration and permit reuse only when still compatible. Actual lock/sleep/orientation combinations remain SKIP.

### A03 · P2 · Permanent H.264 failure starts an unbounded replay loop — S/D

**Location:** `Mac/MacSender.swift:2337–2339`, `handleEncodeFailure`; `scheduleDropReplay`, `armDropReplay`; `Mac/CaptureRecovery.swift`.

**Trigger:** H.264 encoding repeatedly returns `kVTInvalidSessionErr` with a cached frame. Every failure arms another replay after 30 ms, with no encoder reconstruction, retry budget or terminal failure.

**Evidence:** [PersistentEncoderFailureProbe.swift](../tools/audits/2026-10-26/PersistentEncoderFailureProbe.swift) runs the production error/timer methods and replay policy with an always-failing encoder stub: 47 encode attempts in 1.6 seconds, 0 rebuilds, 0 terminal failures, next retry still armed. Exact attempt count is scheduling-dependent.

**Impact:** unnecessary work and frozen video with continuing heartbeats. A Mac receiver that already received video has no remaining first-video timeout. Baseline H.264 error handling was also incomplete; the new regression is the autonomous, unbounded replay even without new capture frames. Classify fatal errors and bound retry/rebuild attempts. Physical encoder failure injection remains SKIP.

### A04 · P2 · Arrangement restoration confuses edge alignment with adjacency — S/D

**Location:** `Mac/DisplayArrangement.swift:145–151`, `side(of:relativeTo:preferring:)`.

**Trigger:** an edge aligns with the main screen while the rectangles do not overlap on the other axis. The main-screen branch bypasses the actual-neighbor remapping.

**Evidence:** [ArrangementProbe.swift](../tools/audits/2026-10-26/ArrangementProbe.swift) calls production geometry with a disposable preferences domain: main `(0,0,1920,1080)`, lower screen `(0,1080,1920,1080)`, virtual screen `(1920,1580,1080,1920)`, new size `1920×1080`. Restore returns y=`1080`; actual-neighbor remapping preserves y=`1580`: a 500-point jump.

**Impact:** a rotated/resized desktop unexpectedly moves. Require perpendicular overlap, allowing intentional corner contact. No physical display arrangement was changed for this reproduction.

## Additional current-source findings

These are broader current-project findings, not all regressions introduced by PR #18.

### A05 · P2 · LAN auto bitrate interprets encoder skips as network congestion — S/D

**Location:** `Mac/AdaptiveBitrateController.swift:243–250`, `congestionReason`; `Mac/MacSender.swift`, pre-encode drop accounting, `schedulePing`, `bitrateTransport`, `updateAdaptiveBitrate`.

Pre-encode budget skips and encoder output drops share `dropsThisWindow`. The receiver-driven controller treats any nonzero Mac drop in the LAN (`.wifi`) category as congestion, even with no pending sends, no receiver pressure, equal sent/encoded FPS and stable RTT/frame age. Ethernet TCP also uses this category. Mac receivers use the separate local controller; this finding's receiver-driven path concerns iOS/Android receivers reporting `stats`.

**Evidence:** [ParameterPolicyProbe.swift](../tools/audits/2026-10-26/ParameterPolicyProbe.swift) calls production controllers with `pendingSends=0`, sent/encoded=`60/60`, RTT=`2 ms`, frame age=`8 ms`, receiver queue/drops=`0`, one Mac drop per 2-second sample. LAN goes `40 → 8 Mbps` after eight decreases; the otherwise identical USB controller does not decrease. This proves a false network attribution under those inputs, not a measured frequency or visual-quality score.

**Fix direction:** distinguish encode-limited skips from transport/receiver pressure; use causal congestion evidence before cutting bitrate. Do not simply raise the minimum bitrate and make poor links worse.

### A06 · P2 · iOS flushes the reference chain on the first transient backpressure signal — S/D

**Location:** `iOS/PhoneReceiver.swift:785–791`, `handleAnnexB`; `requestKeyframeIfNeeded`. Compare `Mac/Receiver/MacVideoRenderer.swift`.

The default system video path flushes immediately when `isReadyForMoreMediaData` is false, then rejects predictive frames until a keyframe. A temporary full queue is not itself a decoder failure. The Mac path already tolerates bounded pressure (two additional frames / under 50 ms); the iOS path does not.

**Evidence:** [IOSBackpressureProbe.swift](../tools/audits/2026-10-26/IOSBackpressureProbe.swift) uses the exact production admission excerpt with a fake layer: one not-ready P-frame causes one flush; the next 30 P-frames are all rejected even though readiness is restored; a keyframe resumes admission. The 30-frame sequence is an injected recovery-wait scenario, not a measured freeze duration. Actual keyframe response can be much faster, or delayed by the one-second request throttle / A01.

**Fix direction:** preserve references across brief occupancy pressure with a bounded policy, then flush/request recovery for sustained backlog. Test on devices before choosing the bound. Apple's `AVQueuedSampleBufferRendering.isReadyForMoreMediaData` documentation allows bounded real-time enqueueing while false; it does not justify unbounded queues.

### A07 · P2 · Android stretches video when source and receiver aspect ratios differ — S/R/V

**Location:** `AndroidReceiver/app/src/main/java/app/opendisplay/android/MainActivity.java:254–259,303–314`, `onStreamConfig` / `buildUi`; `H264SurfaceDecoder.configureAttempt`.

The output `SurfaceView` and cursor overlay always fill the parent; stream width/height do not update an aspect-fit rectangle. MediaCodec's scale-to-fit mode fills the Surface dimensions. A landscape mirror or a 16:9 desktop preset on a different-aspect panel is visibly distorted.

**Evidence:** [run-android-ux.py](../tools/audits/2026-10-26/run-android-ux.py) extends the existing disposable Android test harness, streams actual synthetic H.264 `640×360`, and captures the production UI. A `120×120` black square appears as a **200×774-pixel** black interior in a `1080×2340` screenshot. The region measurement excludes filtered edges. This is real emulator rendering of synthetic content, not a fabricated connection screenshot or a physical display measurement.

**Fix direction:** share one aspect-fit video rectangle between Surface, cursor and input mapping. Merely changing touch coordinates would leave the picture distorted. Cover portrait/landscape, 4:3/16:9, resize and letterbox input rejection.

### A08 · P2 · Android's metrics-off switch leaves the old metrics visible — S/R/V

**Location:** `MainActivity.java:485–490,906–909`, metrics checkbox and `refreshStreamingStatus`.

Disabling `KEY_SHOW_METRICS` calls `refreshStreamingStatus`, which immediately returns without replacing the already-rendered metric string. Later statistics also return early. The stale numbers remain until another status event overwrites them; hiding the separate status overlay masks the problem but is a different control.

**Evidence:** the Android UX fixture starts a real synthetic video stream, unchecks “显示延迟和帧率”, verifies the checkbox is false, closes settings and still finds the old metrics in the accessibility tree and screenshot. Both status and detailed metrics default to true; in the portrait capture the verbose card occupies much of the upper image.

**Fix direction:** render a concise connection status immediately when details are disabled; consider opt-in detailed metrics separately from the persistent settings action.

### A09 · P2 · Manual bitrate options can disagree with the effective session limit — S/D

**Location:** `Mac/SenderSettingsView.swift:11–16,87–103`; `Mac/StreamEncodingPolicy.swift:47–60`; `Mac/MacSender.swift`, `bitrateTransport` / `selectedBitrate`.

The settings picker assumes HEVC unless H.264 is forced and assumes USB unless LAN is forced. With both set to Auto it offers 160 Mbps. A real LAN session clamps this to 100 Mbps; USB H.264 also clamps it to 100 Mbps. Changing codec/transport can remove the stored preset from the picker without normalizing it: normalization runs only when the bitrate mode changes. `SessionRow` does show the effective target, but the picker gives no reason for the mismatch.

**Evidence:** production-policy probe: Auto assumptions offer 160; actual LAN HEVC and USB H.264 both select 100. Source review confirms the missing codec/transport normalization. The Mac settings UI itself was not operated in this follow-up.

**Fix direction:** explicitly separate requested/effective targets and explain limiting codec/transport per session; reconcile invalid picker selections. Keep runtime clamps until evidence supports changing them.

### A10 · P2 · iOS reads obsolete Mac drop/queue telemetry keys — S/D

**Location:** `iOS/PhoneReceiver.swift:500–504`; `Mac/StreamEncodingPolicy.swift`, `StreamDebugStats.pingJson`; `iOS/ReceiverPerformanceView.swift`.

The current sender emits `droppedFramesMac` and `queueDepthMac`, while iOS still reads only `drops` and `pending`. Fresh iOS state therefore keeps displaying zero Mac drops and no pending queue despite nonzero values on the wire. Android already accepts both key generations.

**Evidence:** the parameter probe serializes production sender metrics `9/2`; the consumer's `drops/pending` keys are absent, leaving its initial `0/0`. This is a contract mismatch, not an estimator-accuracy question.

**Fix direction:** accept current keys with legacy fallbacks and add a sender-to-iOS telemetry contract test. Label enqueue FPS and capture-to-enqueue timing accurately; they are not measured panel refresh or photon latency.

## Parameters and experience tradeoffs

The rows below separate reproducible policy effects from hypotheses requiring hardware measurements. They are not permission to relax safety limits wholesale.

| ID | Current parameter / behavior | Evidence and user impact | Next decision |
| --- | --- | --- | --- |
| T01 | Apple shared envelope `4096×2304×60` pixels/sec; mandatory H.264-compatible fallback; discrete 30/60/90/120 choices | D: a 4K/120 request at High becomes `3840×2160@60`; Balanced becomes `2880×1620@120`. The explicit FPS setting is a ceiling, not a guarantee or an FPS-first optimizer. | Explain the limiting dimension and offer a clarity/refresh tradeoff. Higher per-device envelopes require decoder and fallback evidence. |
| T02 | Mac local bitrate recovery requires exactly zero pending sends on healthy 0.2-second samples for 5 seconds, +7%, capped at original target | D: after a decrease to 35.2 Mbps, 60 seconds at one pending send out of three, constant oldest age 2 ms and equal sent/encoded FPS gives no recovery. Fully drained samples do recover. | Consider healthy queue age/completion rate, not only zero occupancy. Prove improvement under continuous scrolling, not just idle desktops. |
| T03 | Auto decreases 20% from receiver signals / 12% locally; increases 7% per healthy 5-second interval | S/arithmetic: ideal 8→40 Mbps recovery needs about 24 increases / 120 seconds; gaps and pressure can extend this. A05 can make this unnecessary degradation. | Fix attribution first; then measure recovery speed, oscillation and text clarity. |
| T04 | Manual/Auto H.264 max 100 Mbps; HEVC LAN 100 / USB 160; Benchmark max 200 | S/D: Ethernet is in the LAN bucket; available picker options can mislead (A09). No physical evidence establishes that 160/200 improves latency or quality on the user's link. | Explain caps and distinguish transport evidence; A/B high-detail 4K text/motion before increasing them. |
| T05 | Average bitrate and one-second DataRateLimits use the same bitrate | S: bursts and IDRs share a strict one-second budget. The prior offscreen 4K probe did not measure actual network bitrate or prove undershoot. | Measure actual throughput, frame-size distribution, IDR recovery and quality before changing peak/average headroom. |
| T06 | Sender qualities: High 100%, Balanced/Gaming 75%, Low 50%; Android also offers Native/75%/50% | D: a 2560×1600 receiver at 75% plus sender Balanced produces 1440×900: 56.25% per axis, 31.64% of native pixels. Defaults are High/Native, so this is not default degradation. | Show final encoded pixels and avoid unexplained double scaling; desktop size and encoded resolution need distinct labels. |
| T07 | Android transport→decode FIFO 12 and decoder-input FIFO 12; no age deadline in these FIFO policies | S/D: 24 queued frames represent 400 ms at 60 fps or 200 ms at 120 fps **if both fill**. These are capacities, not fixed or observed delays. | Measure occupancy and frame-age tails; consider time-based recovery while preserving predictive-frame dependencies. Do not blindly replace compressed P-frames. |
| T08 | Mac encode budgets 1 below 60 / 2 at 60+; send budgets Gaming 1, Balanced/Low 2, High 3; SCK queue depth 8 | S plus earlier D/offscreen probe. Tight budgets can skip on slow encoders; larger budgets can increase latency. Driver frame-delay settings were unsupported in the local 4K probe. | A/B frame age, skipped captures, real presentation and CPU on target hardware. Do not infer extra latency directly from capacity alone. |
| T09 | No explicit 30 fps sender UI; Auto/60/90/120; Auto chooses within capability | S: battery, thermal, weak-link and static-office users cannot directly request 30 through the current picker although protocol policies support it. | Consider a 30 fps / energy-saving choice. No battery-saving amount has been measured. |
| T10 | iOS finger-down delay 120 ms or movement >10 pt; Android down waits for movement or release | D: production Android gesture state emits no down for stationary holding, then down+up together on release. iOS delay helps distinguish two-finger scroll; Pencil has a separate path. | Add explicit stationary hold semantics on Android; tune finger latency without reintroducing accidental clicks during scrolling. Full app mouse gesture behavior remains SKIP. |
| T11 | Hello deadline 5 s; Android handshake stages 1.5/2/3 s; capture retry 3 s; transport backoff 0.5/1/2/4/8 s | S: bounded waits are necessary; stacked reconnect stages can feel slow. There is no current evidence these particular deadlines should all be lengthened/shortened. | Show progress, retry/next action and effective stage; measure cold start, resume and cable replug on slow devices. |
| T12 | Apple input budget 64 / 64 KiB; Android writes 128 queued tasks / 64 KiB; 16 MiB absolute framing; Android pool 32 MiB with 250 ms wait | S and existing boundary tests: these prevent unbounded retained work and stuck input. Overflow intentionally closes the affected session. | Preserve bounds. If real stylus/trackpad bursts saturate them, coalesce eligible motion while retaining release/cancel, rather than making queues unbounded. |
| T13 | Default Android status + detailed metrics enabled; iOS analytics disabled | R/V: Android portrait content is obscured by a verbose card; A08 prevents immediately clearing details. iOS large-text waiting screenshot wraps and pushes actions below the first viewport. | Prefer concise status and opt-in detail. Review scrolling, large text and screen-reader navigation on devices; no blanket accessibility pass is claimed. |

## Additional boundaries to investigate before declaring acceptance

- **B01 — Android cursor bitmap dimensions are not bounded before decode (S, P2 risk).** `OpenDisplayServer.java:614–618` decodes Base64; `MainActivity.java:233–242` calls `BitmapFactory.decodeByteArray` without an `inJustDecodeBounds` dimension check. Outer frame limits bound compressed bytes, not expanded pixels. The Apple peer validates at most 512×512 before image creation. Add a decoded-pixel/geometry bound; no memory-exhaustion payload was executed, and no crash/exploit is claimed. Default authentication reduces exposure; explicit legacy mode still accepts a LAN sender.
- **B02 — Android mirror FPS/capability is derived for a different raster (S).** `MacSender.setupMirror` sizes non-Apple capture from the source display; Android `CodecCapabilities.maxSupportedFps` announces its rate for the receiver's scaled panel. Actual decoder-ready feedback can reduce FPS, but cannot guarantee a source-sized raster is supported. Reproduce on a smaller/slower Android decoder with a large Mac mirror before choosing a limit or renegotiation fix.
- **B03 — iOS has no independent first-video deadline (S).** Its watchdog checks recent bytes, so heartbeats can keep a video-less connection alive. Mac has a 15-second first-video deadline. Add a controlled no-video/heartbeat runtime case; do not call a static desktop after a valid first frame stalled solely because it produces no new frames.
- **B04 — Android accessibility lint remains open.** Lint reports 0 errors / 25 warnings, including `ClickableViewAccessibility`, `DrawAllocation`, hardcoded-text and resource warnings. A custom trust-manager warning is not by itself proof of a TLS bypass: production certificate pinning/admission and live revocation passed the runtime fixture. TalkBack/VoiceOver and complete keyboard navigation were not tested.

## Module and function coverage matrix

The matrix describes what was actually examined in the initial review plus this follow-up. Test names refer to existing repository suites; their passage is not branch-complete coverage.

| Functional group | Source/functions and scenarios examined | Verification / remaining gap |
| --- | --- | --- |
| Mac roles and lifetime | `MacRoleController.select`, `SessionLifetime.start/fail/stop`, `SenderController.replace/retry`; cleanup before replacement, stale callbacks | S/D; role/lifetime suites; interactive rapid switching SKIP |
| Discovery and routes | `DirectCable`, `TransportSelectionPolicy`, `MacLANHandoverPolicy`, controller discovery/dedup/handover; same-ID matching, manual opt-out, retry cap | S/D; real cable/Wi-Fi handover SKIP |
| USB resources | `AndroidAdb`, `AndroidAdbForward`, `Usbmux`, `UsbmuxTLSRelay`; executable resolution, per-session mapping, cancellation/deadline | S/D; ADB owned-forward exercised by emulator; physical USB throughput/replug SKIP |
| Pairing and admission | shared/Android identity, pairing, trust revision, TLS admission, revoke/legacy transitions | S/D/R/V; iOS and Android isolated runtime; production identities untouched |
| Extend / virtual display | `setupExtendExclusive`, display coordinator, topology, arrangement, origin restoration | S/D; A02/A04; no virtual displays created; physical SKIP |
| Mirror | `setupMirror`, main-display selection, source geometry and input target | S; B02; live capture SKIP |
| Capture recovery | `startCapture`, recovery scheduling/reattach/rebuild, source verification, cached-frame replay | S/D; A02/A03; sleep/lock/WindowServer behavior SKIP |
| Codec / FPS / resolution | `PhoneInfo`, `MacReceiverPolicy.plan`, desktop geometry, Apple envelope, Android selected decoder/fallback caps | S/D/R; T01/T06/T09; vendor capability truth and sustained 90/120 SKIP |
| Encoder ownership | callback disposition, generation counters, keyframe tracker, fallback factory, rate properties | S/D and previous offscreen VT probe; A01/A03; Intel driver runtime SKIP |
| Sending / auto bitrate | separate work budgets, local and receiver ABR, framing/oversize policy | S/D; A05, T02–T05/T08; LAN latency/quality A/B SKIP |
| Framing / compatibility | Apple bounded decoder/bitstream, Android V1/V2 epoch/config/sequence, frame pool leases | S/D/R; loopback and synthetic streams; physical old-app interop SKIP |
| Mac receiving | adoption/generation, first-video deadline, HEVC fallback, bounded layer pressure, cursor relay, window/controller | S/D/R loopback; receiver-window/fullscreen and physical presentation SKIP |
| iOS receiving | hello/config, Annex-B admission, AV layer / experimental Metal ownership, liveness/background | S/D/R; A06/B03; actual high-refresh/Pencil hardware SKIP |
| Android decoding | async codec identity, input-index/telemetry ownership, reference-chain recovery, two FIFOs, stall rebuild, Surface/Wi-Fi hints | S/D/R synthetic H.264; vendor HEVC/thermal/high refresh SKIP |
| Input | desktop consent/sequence/release, touch/scroll validation, Pencil versions/actions/budget, view ownership | S/D/R protocol fixture; T10; actual desktop application/pen pressure/drag feel SKIP |
| Mac presentation/settings | sender/receiver/settings/session rows, restart semantics, failure recovery actions, requested vs effective values | S; A09; no new Mac window screenshots or full keyboard/accessibility pass |
| iOS presentation | waiting/onboarding/settings, light/dark, large text, persistent settings action | S/R/V; reviewed contact-sheet subset; landscape streaming and VoiceOver SKIP |
| Android presentation | onboarding/security modes, settings, synthetic stream, ratio and metrics toggle | S/R/V; A07/A08; only disposable API 35 portrait fixture, not all device layouts |
| Metrics / diagnostics | sender ping schema, receiver stats/overlay, ABR inputs, bounded logs, benchmark semantics | S/D; A10; enqueue/render/photon distinction; physical latency not established |
| Update / release / website | latest-batch scripts/pages, distribution tests, GitHub-only artifact rules, update policies/signing boundaries, bilingual checks | S/D/build; no release published, no installed app updated, no new live artifact-signature audit |

## Executed checks and reproducible evidence

Initial review evidence, retained because production source is unchanged:

- 60 standalone Swift suites PASS, including real loopback TCP/TLS and injected Mac receiver pressure/first-video cases.
- XcodeGen + unsigned Mac Debug arm64/x86_64 build PASS; App Intents extraction tool warning only.
- Website `pnpm build`, bilingual documentation check (96 pairs at that point), release static check (v0.3.0 / 8 assets) PASS.
- 12 offline Apple distribution tests, changed shell/Python syntax checks and batch whitespace check PASS.
- Offscreen 4K/60 VT probe with requested 100 Mbps: both policies encoded 180/180 frames; no skipped/failed frames, approximately 60 FPS. `MaxFrameDelayCount`, speed priority and hardware query returned `-12900` on that host. This does not prove actual 100 Mbps throughput, supported frame-delay behavior, Intel performance or two-device latency.

Follow-up checks:

- All seven recorded probe programs PASS in the sense of observing the recorded behavior. Production method excerpts and SHA-256 source snapshot verified. The recovery fixture has a Swift non-Sendable stub-capture warning; it is not an application build warning or an additional production finding.
- Unsigned iOS Simulator build PASS.
- Android `./gradlew --no-daemon test assembleDebug lintDebug` PASS: six registered plain-Java groups; 0 lint errors / 25 warnings. Standard Gradle unit-test tasks report NO-SOURCE; do not count those as extra tests.
- Isolated iOS runtime: actual TLS hello/video, live revocation, plaintext isolation, Pencil V2/V1/denied-action cases, presentation replacement/late teardown, UI captures and background listener shutdown PASS.
- Isolated Android runtime: Keystore persistence/reset/repair, Apple→Android TLS, live UI revocation, explicit legacy transitions (three cycles), synthetic H.264 video, A07/A08 observations and background listener shutdown PASS. Its FPS numbers are emulator/fixture observations, not a performance benchmark.
- Final `pnpm run check:docs` PASS (97 pairs); tracked/new-file whitespace, shell syntax, Python AST, relative links and bilingual finding/parameter ID checks PASS.

Run from the repository root:

```bash
bash tools/audits/2026-10-26/run-probes.sh
python3 tools/test-secure-ios-receiver.py --screenshots build/diagnostics/code-review-2026-10-26/ios-ui
python3 tools/audits/2026-10-26/run-android-ux.py --screenshots build/diagnostics/code-review-2026-10-26/android-ui
```

The probes require the audited source, its `39f97a5` baseline, Swift/macOS and Java. The Android UX runner additionally needs ffmpeg and the existing harness's SDK/API 35 ARM64 system image. Run mobile fixtures sequentially. They own and delete disposable simulators/AVDs; no production application, identity or settings are replaced. The source hash/excerpt check intentionally stops after relevant production edits: update the audit or turn cases into proper fixed-behavior regression tests instead of presenting stale reproductions as current evidence.

Raw logs/images remain under the ignored `build/diagnostics/code-review-2026-10-26/` directory. Durable evidence is this paired report, the [reproduction tools](../tools/audits/2026-10-26/) and their source snapshot. Relevant local files: `recorded-probes.log`, `android-build-tests.log`, `ios-simulator-build.log`, `ios-runtime-ui.log`, `android-runtime-ux.log`, `android-aspect-measurement.json`, and `android-ui/android-synthetic-aspect.png` / `android-metrics-disabled.png`. They are not committed private captures.

Primary API references checked during this review: Apple's `AVQueuedSampleBufferRendering.isReadyForMoreMediaData` documentation and AOSP `MediaCodec.java` scaling-mode documentation. Local retrieved copies are `apple-renderer-readiness.txt` and `android-codec-scaling.txt`; the source/code/runtime evidence above carries the project-specific conclusions.

## Follow-up acceptance, not performed here

Fix A01–A04 with failing state-transition tests first; correct A05/A06 attribution/recovery and A07/A08 visible behavior; repair A09/A10 settings/telemetry contracts. Treat B01 as a bounded-decoding follow-up. Then measure T01–T13 instead of changing all limits together.

For tuning, use identical desktop/video content, one parameter change at a time, recording requested and actual resolution/FPS/codec/bitrate, rendered FPS, frame-age p50/p95/p99, drop reasons, queue peaks, reconnect time, CPU and thermal state. Cover Mac Intel/Apple silicon, iOS/Android device tiers, Ethernet/Thunderbolt/Wi-Fi/USB, 1080p/1440p/4K, 60/90/120, static text/scrolling/video/Pencil, rotation/resume/replug and a long run. Agree thresholds from a measured baseline; this review does not invent latency targets.

**Physical SKIP:** independent online display not established; no interactive Mac capture, receiver-window or virtual-display test; no physical two-device LAN/USB, Intel driver, sleep/lock, long-duration thermal/battery, stylus or screen-reader acceptance. These remain explicit gaps, so “complete product acceptance” would be an overstatement.

[English](reliability-experience-upgrade.md) | [简体中文](reliability-experience-upgrade.zh-CN.md)

# Reliability and experience upgrade

Source development, started 2026-10-26. Baseline: `01613ef`; the [audit](code-and-experience-audit-2026-10-26.md) is historical evidence, not a claim about the updated source or a published release.

## Scope and acceptance

1. **Session recovery (A01–A04):** retire keyframe ownership with its generation; apply changed receiver configuration after interrupted capture; bound encoder failure recovery; preserve actual display adjacency on rotation. Verify replacement/late callback interleavings, fatal failures and multi-display geometry without creating virtual displays.
2. **Video policy (A05, A06, A10, T02, T03):** distinguish encoder pressure from network congestion, recover bitrate with a healthy active queue, preserve predictive frames across brief decoder backpressure, and consume current/legacy telemetry. Verify production policies and wire contracts.
3. **Receiver experience (A07, A08, B01–B04, T07, T10, T13):** aspect-correct Android video/cursor/input; concise default status; bounded cursor decode and video readiness; age-aware decode recovery; stationary touch holds and accessible controls. Exercise isolated Android/iOS runtime fixtures with synthetic video.
4. **Settings and performance (A09, T01, T04–T06, T08–T12):** truthful requested/effective settings, explicit 30 fps, clear resolution/refresh tradeoffs and actionable connection feedback. Retain protocol/resource bounds; document evaluated parameters and unresolved hardware experiments.
5. **Completion:** relevant regressions per commit, both Apple builds, Android tests/build/lint, web/docs/release checks, security/lifecycle runtime fixtures, self-review and reproducible local artifacts. Record source, automated, UI and physical evidence separately.

Compatibility: preserve preference keys, project/package/bundle IDs, framing, service discovery, pairing, signing/update identities and attribution. Sender/receiver roles remain exclusive. No public release is implied. Historical snapshot probes remain tied to the baseline; new regressions must exercise fixed production behavior.

## Implementation and verification ledger

Round 1 implements A01–A04: immutable keyframe leases with retirement, capture-hello ownership, bounded encoder retries/rebuilds, and overlap-aware display placement (including previously saved invalid side records). Fatal errors rebuild at most twice; transient busy/output drops retry at most three times per round; five seconds of healthy output restores the budget.

Verified: keyframe replacement/duplicate callbacks; persistent/transient encoder failure exhaustion; geometry regression fails on the baseline and passes after repair; current-method capture fixture fails against `01613ef` and passes for changed/unchanged/locked recovery. Universal arm64/x86_64 unsigned Mac Debug build passes. No physical capture/recovery claim.

Round 2 implements A05, A06, A10, B03, T02 and T03. Mac drops remain diagnostic, while network decisions require send/receiver evidence. Healthy active send queues can recover. Below the original target, Auto restores 20% after 3 healthy seconds (receiver sampling may extend this); above it, probing remains 7% / 5 seconds. Mac local recovery never exceeds its original target. Apple receivers share the two-frame / 50 ms backpressure policy. iOS reads current and legacy ping keys and drops video-less connections after a separate 15-second deadline; static desktops after first video are exempt.

Verified: all 61 Swift suites, actual loopback receiver pressure/reconnect checks, current iOS admission fixture, telemetry serialization, and both Apple target builds. Synthetic policy recovery from 8 to 40 Mbps now completes within 38 seconds in the test. This is not a measured network result.

## Receiver and settings completion

Round 3 fixes A07/A08 and implements B01/B04, T07/T10/T13: Android video, cursor and touch share an aspect-fit Surface; new installations show concise status; toggling details replaces visible text immediately. Settings contain selectable full diagnostics. Cursor images are limited to 512 KiB compressed and 512×512 pixels, with finite normalized geometry checked before decode. A 120 ms, gesture-owned timer enables stationary holds and cancels on scroll, pause, resize or session change. Movement slop uses pixels independently on each axis. Both 12-frame FIFOs share a 150 ms receive-to-codec deadline, including retained packet copies; expiry clears dependent frames and requests a keyframe. System rotation is respected; touch release calls the custom Surface's accessibility click hook and cursor drawing reuses its rectangle.

Verified: seven Java groups, Debug APK build and lint (0 errors / 21 warnings, down from 25). ClickableViewAccessibility and DrawAllocation are cleared. Remaining warnings concern toolchain updates, obsolete API checks, resource/icon placement, localization and the intentional pinned trust manager; they are not claimed resolved. Real isolated Android Keystore/TLS/revocation/background checks pass. Synthetic 640×360 video now renders the square at approximately 200×200 instead of the baseline 200×774. UI-tree-driven input confirms black-bar rejection, normalized center taps and a stationary press that arrives before release. This is emulator evidence, not physical touch/latency or full TalkBack acceptance.

Round 4 fixes A09, B02 and improves T01/T06/T09/T13. Settings now normalize unavailable manual presets to the nearest valid option in one transaction; Auto lists potentially supported requests and each session explains its effective codec/transport clamp. Device cards show encoded raster, codec, target FPS and actual throughput. Apple receivers offer resolution/frame-rate priority and an explicit 30 fps ceiling. Priority also ranks alternative decoder envelopes correctly; the new alternative-envelope regression failed before the fix and passed afterward. Android/legacy mobile mirrors fit the announced decode raster while preserving aspect ratio. iOS keeps connection settings pinned above the bottom safe area; body text retains accessibility sizing, with only branding capped.

Verified: settings persistence/normalization and legacy keys, 30 fps, 4K detail versus 120 fps raster tradeoffs, multiple capability envelopes, landscape/portrait mirror bounds, both Apple builds and iOS light/dark/large-text screenshots. The isolated iOS TLS test now keeps a heartbeat-only session alive at 11 seconds, observes it disconnected at 18 seconds, reconnects, then keeps a static valid picture connected for 16 seconds. Existing Pencil V2/V1/denied-action, presentation ownership, revocation and background tests continue to pass.

## Finding closure

These are source/regression outcomes; physical acceptance is separate. The original [module coverage matrix](code-and-experience-audit-2026-10-26.md#module-and-function-coverage-matrix) remains the inventory. This work does not claim every line, device or branch was exercised.

| Item | Source result | Regression evidence |
| --- | --- | --- |
| A01 | Fixed: keyframe leases retire with the old encoder/wire generation | Keyframe replacement, no callback, duplicate/late callback tests |
| A02 | Fixed: fast reattach requires the actually applied hello | Current production recovery method: baseline failure, corrected pass |
| A03 | Fixed: retries/rebuilds end in actionable failure after a bounded budget | Persistent/transient failure and healthy-reset policy tests |
| A04 | Fixed: adjacency requires perpendicular overlap; old saved sides revalidated | Actual 500-point jump regression: red before, green after |
| A05 | Fixed: encode/capture skips alone do not imply LAN congestion | Healthy send/receiver metrics with continuing Mac drops remain stable |
| A06 | Fixed: brief Apple backpressure preserves references; sustained pressure requests recovery | Shared flow suite and current iOS admission fixture |
| A07 | Fixed: aspect-fit video/cursor/touch rectangle | Synthetic square measurement and real emulator touch |
| A08 | Fixed: metrics-off immediately restores concise text | Actual production settings toggle in emulator |
| A09 | Fixed: requested/effective bitrate and valid preset normalization | Settings/encoding policy tests and builds; Mac visual acceptance pending |
| A10 | Fixed: current telemetry keys with legacy fallback; explicit zero clears | Real sender ping serialization consumed by shared parser |
| B01 | Implemented: cursor bounds before bitmap allocation | Size/dimension/NaN policy tests; no memory-exhaustion attack executed |
| B02 | Implemented: mirror within announced receiver raster | Large-source/portrait geometry tests; physical vendor decoder pending |
| B03 | Implemented: independent 15-second first-video timeout | Actual TLS heartbeat-only timeout and static-desktop exemption |
| B04 | Targeted repairs: click hook, draw allocation, rotation/backup attributes | Lint 0 errors / 21 remaining warnings; full screen-reader acceptance pending |

## Parameter decisions

| ID | Decision and reason |
| --- | --- |
| T01 | Add explicit resolution/frame-rate priority; keep the advertised 4096×2304×60 throughput envelope and H.264-safe fallback. Fitting a smaller raster enables high refresh without inventing decoder capability. |
| T02 | Allow healthy active queues to recover; use age, completion delay and ≥95% send/encode ratio. Nonzero occupancy alone is not a fault. |
| T03 | Restore the initial target at +20% / 3 healthy seconds, retain +7% / 5 seconds above it, with a default 3-second cooldown. Synthetic 8→40 Mbps ≤38 seconds; physical oscillation/quality pending. |
| T04 | Keep H.264 100 Mbps, HEVC LAN 100 / USB 160, Benchmark 200 ceilings. Explain actual clamps; no new physical evidence supports larger production ceilings. |
| T05 | Keep the existing average/one-second peak rate relationship. No new physical IDR/quality/throughput data supports changing burst headroom. Measure it before choosing a new value. |
| T06 | Display final encoded pixels and explain double scaling; keep High/Native defaults. Mirror fits the receiver raster. |
| T07 | Add one 150 ms receive-to-codec age limit across both Android FIFOs; preserve dependency recovery and capacity 12. It is not a network or end-to-end bound. |
| T08 | Retain encode/send/SCK budgets. A larger queue alone does not establish smoother presentation; physical capture/latency A/B is needed. |
| T09 | Expose 30 fps with preference round-trip and legacy compatibility. It is an explicit lower workload choice; no battery-saving percentage is claimed. |
| T10 | Android stationary press after 120 ms, movement can start sooner, second finger cancels for scroll. Match existing iOS disambiguation intent; retain bounded input. |
| T11 | Keep protocol deadlines and bounded reconnect schedule; retain actual stage/status plus existing retry/cancel actions. Add independent iOS first-video recovery rather than allowing heartbeats to mask missing video. |
| T12 | Keep input/framing/pool limits. No evidence warrants unbounded work; future motion coalescing must preserve release/cancel. |
| T13 | Android detailed metrics opt-in for new users, immediate concise rendering, selectable diagnostics; iOS settings stay reachable with large text. Preserve explicit old metric preferences. |

## Final verification and local artifacts

- 61 Swift suites plus current-method capture/admission fixtures pass. The capture fixture's non-Sendable OS stub warning remains a test-fixture limitation, not an app build failure.
- Universal arm64/x86_64 Mac Debug and iOS Simulator builds pass. A Mac Debug app is additionally signed with the existing pinned Apple identity and passes the repository signature/identity check; this is not notarization or a published release.
- Seven Android Java groups, Debug APK build and lint pass. Standard Gradle unit tasks remain NO-SOURCE; they are not extra tests.
- Real Apple↔Java mutual TLS, Mac/iOS Keychain, secure iOS and extended Android runtime suites pass in disposable namespaces/simulators/AVDs. Production applications and transport identities are untouched.
- Final gate passed: website TypeScript/client/SSR/prerender and generated-site checks, 98 bilingual documentation pairs, release links (v0.3.0 / 8 assets), 12 Apple distribution tests, 20 Mac signing policy tests and 36 brand assets.
- Inspected evidence: Android synthetic aspect/metrics screenshots and actual input; iOS waiting/onboarding/settings light/dark and maximum accessibility text. No Mac window or full screen-reader acceptance is claimed.

Reproduce with the commands in [development](development.md), including `tools/test-android-experience.py` and the sequential mobile runtime scripts. Logs/screenshots are local and ignored under `build/diagnostics/upgrade-2026-10-26/`; final development artifacts are under `build/deliverables/reliability-experience/`. The artifact README records exact revision, hashes, signing/install boundaries and local use. Source changes do not alter the public v0.3.0 release/feed.

## Commits

Development branch: `codex/reliability-experience`, working remote `displayweave` (the upstream `origin` is read-only for this work). `181e52d` records the audit; `9bfd470` fixes recovery ownership; `944cc95` fixes video/bitrate/telemetry; `ffd1e7d` repairs Android geometry/input/queues; `42af3a7` adds display priorities, negotiated-setting feedback and the iOS experience improvements. The final documentation commit records acceptance without changing the built production sources.

## Upstream assessment

Both remotes were refreshed. Upstream `07d6b78` updates v1.28 appcasts; `e8a7f0f` (2026-10-24) introduces Android USB accessory mode and replaces its ADB path; `df1872a` (2026-10-24) and `b664802` (2026-10-23) are the earlier ADB/Android work. The local receiver already has distinct authenticated transport, framing and recovery policies. The accessory migration is deferred pending protocol/security integration and real accessory hardware; upstream branding, signing and update metadata are not copied. Previously selected Mac recovery work remains integrated and receives the fixes above.

## Physical acceptance

Pending: real Mac capture/virtual-display recovery and rotation, two-device LAN/USB latency and endurance, high-refresh decoder envelopes, Intel runtime, energy consumption, VoiceOver/TalkBack and real touch/Pencil interaction. Verify an independent online display before interactive virtual-display tests. Never restart WindowServer or remote access to clean up tests.


Physical acceptance procedure:

| Area | Run and acceptance |
| --- | --- |
| Capture/lifetime | With an independent display online, test mirror and extend, rotate, sleep/lock/resume and reconnect with changed resolution. Verify current configuration, bounded recovery, stable screen placement and cleanup before role/session replacement. |
| Performance | On Apple silicon and Intel senders plus iOS/Android tiers, compare 30/60/90/120 targets at 1080p/1440p/4K over LAN/USB where supported. Record encoded/rendered FPS, frame-age p50/p95/p99, queue peaks, bitrate, drops, CPU/thermal state and visual text/motion; compare one parameter at a time. |
| Endurance/input | Run 30-minute and 2-hour sessions with controlled congestion, rotation/replug and touch/Pencil/keyboard input. Check for retained resources, stuck buttons, recovery loops and oscillation; do not replace missing measurements with simulator timing. |
| Accessibility | Inspect Mac minimum/default windows, keyboard focus and VoiceOver; inspect both mobile orientations, largest text, TalkBack/VoiceOver, settings reachability, drag/scroll cancellation and black-bar rejection on physical devices. |

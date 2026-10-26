[English](source-upgrade-audit-2026-10-16.md) | [简体中文](source-upgrade-audit-2026-10-16.zh-CN.md)

> Historical record: versions, commands and conclusions describe the original snapshot. Use the [current documentation](../../README.md) for present-day instructions.

# Source upgrade audit — 2026-10-16

This closes the source upgrade defined in [the plan](../plans/upgrade-plan.md): project instructions, four UI surfaces, selective upstream integration and a lifecycle/network review. Baseline: `83581c5`; implementation through `7d78a9a`. The earlier Mac-to-Mac implementation is part of PR #11. Published downloads remain `v0.2.1-p6`; this work does not create a release or claim physical two-Mac performance.

## Completed rounds

| Commit | Result |
| --- | --- |
| `d06404d` | AGENTS.md, contributor workflow, current official OpenAI project guidance and verification boundaries. |
| `a202fbb` | Bilingual UI contract and upgrade acceptance plan. |
| `ba89cf5` | Mac connection workspace/settings and iOS screen/model decomposition. |
| `defe049` | Android adaptive receiver UI, bilingual responsive website, metadata and hydration checks. |
| `00e2806` | Selected upstream startup recovery, delayed touch-down and bounded Apple logging. |
| `7d78a9a` | Apple shared frame/cursor limits, stale-connection isolation, input/geometry validation, permission timer release and Android control backpressure. |

Each implementation round passed its affected build/test gate before commit. The following evidence describes the final source state; it does not reinterpret older release reports.

## UI implementation

- **Mac:** send/receive workspace, device/session status and transport actions; separate quality/general/permissions settings via gear or Command-comma. Entry, controller, session, permission monitor, settings and update views have explicit files. Main window is resizable with a 480×440 minimum; the 480×640 menu panel and receiver form scroll. Failed startup exposes retry with a new sender pipeline.
- **iOS:** screen, waiting, onboarding, settings, performance, model and video adapter split. Waiting/help and settings scroll. A visible 44-point settings control works while streaming; shaking remains optional. Onboarding no longer conflates mirroring and extending.
- **Android:** shared `ReceiverUi` styles use dp spacing, adaptive day/night colors and consistent controls. The waiting content is width-bounded, instructions are grouped by connection path, settings scroll, and hiding the performance overlay leaves settings reachable.
- **Website:** shared tokens and semantic sections, keyboard/touch navigation, mobile menu with Escape and close-on-navigation, bilingual metadata, focus states and source-only Mac receiver disclosure. Static rendering uses matching hydration boundaries. Unused components/dependency were removed; TypeScript and generated-site assertions run in `pnpm build`.

See [the UI standard](../../development/ui-guidelines.md) for the maintained contract.

## Upstream decision

Upstream `origin/main` was fetched at `b9eec1f232fb5ea571c87e8392379a84f47b237f`. A whole-tree merge against the UI round had **23 conflicts**. Useful behavior was ported selectively with attribution: startup cleanup/retry (`87b000b`, `c27e538`), bounded logging (`19481a6`), and delayed single-touch commitment (`04590ed`). Earlier Mac receiver adaptations are retained. The [integration review](upstream-integration-2026-10-16.md) records all decisions; upstream history is not marked fully merged.

DisplayWeave IDs, preference keys, Bonjour/wire contracts, signing identities, feeds, public version and Android recovery policy remain compatible. Full private-display recovery, per-device desktop sizing, Mac HEVC, cable discovery, Pencil, remote shutdown and force-update changes remain deferred with rationale.

## Audit fixes and evidence

| Finding | Fix / verification |
| --- | --- |
| iOS accepted an unchecked 32-bit payload length | Both Apple receivers use `Shared/ReceiverFrameDecoder`, rejecting zero or >16 MiB before accumulating payload. The actual old simulator receiver failed the invalid-length loopback test; the updated app passes. |
| Old iOS socket/listener callbacks could affect replacements | Queue-owned lifecycle, listener identity/generation, immediate connection detachment, captured-socket goodbye and bounded retry. Replacement liveness, reconnect and background listener shutdown exercised in Simulator. |
| Unsafe cursor pixel allocation and geometry | Shared decoder inspects metadata before image allocation; sprite ≤512×512, base64 ≤256 KiB, finite anchor and normalized size. Regression rejects compressed oversized images, invalid geometry and oversized input; valid images pass. |
| Peer geometry or scroll conversion could overflow | Validate receiver geometry and pixel area before arithmetic; reject nonfinite coordinates, clamp normalized input and scroll conversion. Extreme integer/float regression cases pass. Interrupted drags release on stop, target change and disconnect. Physical CGEvent behavior remains unverified this round. |
| Permission polling retained its owner | Weak timer closure and invalidation. Lifetime test failed before the fix and passes afterward. |
| Android control traffic accumulated during blocked writes | One writer with 128 queued tasks, ≤64 KiB/control payload; two reader workers with two queued tasks. Queue overflow closes the affected connection rather than losing only a release event. Deterministic blocked-writer test failed before the fix and passes with replacement/stale-send/oversize coverage. |
| Failed or replaced senders could retain resources | `SessionLifetime` stops once, waits for suspended startup, and cleans failed starts. Controller waits for old cleanup during settings/transport replacement and Android recovery; late ADB results are removed when role/transport no longer admits them. |
| Apple logs had no total growth bound | Current and previous file each ≤2 MiB, entry ≤8192 bytes and ≤256 queued entries. Rotation, concurrent writes, UTF-8 truncation and backpressure tests pass. |
| Two-finger scroll began with a click | Delay touch-down until release, 10-point drag or 0.12-second hold; second finger suppresses pending click. Pure policy tests pass; real touch acceptance remains pending. |

## Final local verification

| Check | Result |
| --- | --- |
| Standalone Swift | **32 suites PASS**, including real H.264 loopback, busy rejection, frame limits, reconnect, role isolation, startup cancellation, log limits, touch policy, input, timer and cursor guards. |
| macOS Debug | **PASS**, arm64 + x86_64 universal build. Intel runtime not exercised. |
| iOS Simulator build | **PASS**; latest build installed and loopback regression rerun successfully. |
| Android | **PASS**, `./gradlew --no-daemon test assembleDebug`, six JVM self-test groups. |
| Website | **PASS**, TypeScript, production client/SSR build, prerender and generated-site assertions. |
| Browser UI | **PASS**, English/Chinese × 1440/768/390/320 px; menu, Escape, hash navigation, FAQ, overflow and browser-error checks; reduced-motion mode inspected. |
| iOS UI | **PASS for inspected states**, iPhone 17 Pro / iOS 26.5 Simulator: onboarding, waiting, settings, light/dark and maximum accessibility font with scroll access. |
| Documentation/release links | **PASS**, bilingual pair gate and existing `v0.2.1-p6` seven-asset link check. |
| Whitespace | **PASS**, `git diff --check`. |

Reproduction commands live in [development.md](../../development/workflow.md). `python3 tools/test-ios-receiver.py` is an opt-in test against an already foregrounded Simulator receiver on loopback port 9000; it sends synthetic frames only and waits up to 10 seconds for initial listener readiness. It is not a physical-device or video-quality benchmark.

Remote CI must pass on the final PR head before main integration. PR #11 records the final checks and merge; main/remote equality is verified after integration. No new binary release is part of this source gate.

## Explicit remaining acceptance

1. **Two physical Macs:** both directions, mirror/extend, Wi-Fi/Ethernet, display hotplug, real sleep/wake, macOS 14/15 and Intel runtime. Record codec, resolution, target/rendered FPS, reconnect time and memory; follow [Mac-to-Mac acceptance](../../guides/mac-to-mac.md).
2. **Mac visual and virtual-display cleanup:** the development app launched, but the current closed-lid/headless session could not capture a usable window image. No new virtual display was created. Repeat main/settings/menu/receive/fullscreen and cleanup with an independent online display. Earlier synthetic-display evidence remains in the Mac design report, not a new UI pass.
3. **Android visual and mobile input:** no Android emulator/system image or attached device was available for this round. Check light/dark, font scaling, rotation, system bars, accessibility and live settings on hardware; recheck tap/drag/two-finger behavior on iOS and Android.
4. **Endurance:** two Android receivers, controlled same-condition USB/Wi-Fi, 30-minute and 2-hour runs remain pending. Build, policy and simulator evidence cannot establish sustained 60/120fps.

These acceptance items constrain runtime/release claims. The source iteration ends with the implemented scope and automated gate complete, without presenting the hardware matrix as completed.

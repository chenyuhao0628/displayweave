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

## Physical acceptance

Pending: real Mac capture/virtual-display recovery and rotation, two-device LAN/USB latency and endurance, high-refresh decoder envelopes, Intel runtime, energy consumption, VoiceOver/TalkBack and real touch/Pencil interaction. Verify an independent online display before interactive virtual-display tests. Never restart WindowServer or remote access to clean up tests.

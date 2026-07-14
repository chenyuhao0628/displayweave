[English](current-remediation-plan.md) | [简体中文](current-remediation-plan.zh-CN.md)

# Current Remediation Plan

The static remediation is complete in the local worktree. Preserve the following review boundaries when publishing it:

1. **PR A — Async MediaCodec ownership and stale callback safety:** decoder-generation gating, strict input-index ownership, bounded rendered telemetry, coalesced terminal recovery, and deterministic callback-state tests.
2. **PR B — Reference-chain correctness:** HEVC IRAP/CRA recognition and deterministic keyframe-wait/recovery coverage.
3. **PR C — Codec/FPS capability negotiation:** bind advertised limits to default runtime candidate ordering and cap HEVC preference to the selected H.264 fallback's common limit.
4. **PR D — Generation-scoped Mac work accounting:** encoder-generation ownership plus peak and unmatched-completion counters. Keep the existing work budgets until measured A/B evidence supports changing them.
5. **PR E — Metrics, CI, release, and documentation:** reset-safe GC window deltas, authoritative Swift self-test runner, CI gates, bilingual audits, and release/feed verification.

Remaining validation is hardware-only: execute the documented WiFi/USB, codec, refresh-rate, recovery, and Legacy matrix when devices are available. Until then every such claim remains **Pending**. The buffer pool remains design-only; do not implement it until buffer lifetime and ownership are proven with measurements.

Every PR must preserve Legacy output byte-for-byte and must not convert a source-test result into a physical-performance claim.

[English](current-drop-attribution-audit.md) | [简体中文](current-drop-attribution-audit.zh-CN.md)

# Current Drop Attribution Audit

Baseline: `79cbf90`; physical validation: **Pending**.

## Classification result

- `REFERENCE_CHAIN_BROKEN` is correctly non-congestion: it is a recovery state, not direct evidence of network pressure.
- `LATEST_SLOT_REPLACED` and `DECODER_INPUT_UNAVAILABLE` are classified as congestion-relevant, but the ABR labels sustained receiver evidence as `android-decoder-throughput`; it must not be described as proven network congestion.
- `IMPORTANT_FRAME_PROTECTED` is congestion-relevant because it occurs under occupied latest-slot pressure, although the protected incoming frame itself is intentionally discarded without breaking the retained important frame.
- Stale generation/session/config, malformed input, oversize, Surface loss, reconfigure, and transport failures are correctly excluded from ABR congestion counts.
- Transport read/write failure records one Drop event; the subsequent disconnect does not add another Drop, so it is not double counted.
- A latest-slot replacement followed by reference-chain break records two distinct discarded frames: the displaced pending frame and the rejected new dependent frame. This is not same-frame double counting.
- Window counters reset after publication while totals persist. `lastEvent` resets with the window and events are admitted only after current-generation checks.

## Open issues

- Runtime codec exceptions can still generate repeated exception/keyframe events without a unified bounded recovery transition (P1).
- Recovery frequency should be reported separately from congestion Drop totals and used as evidence for FPS/resolution limiting, not direct bitrate reduction (P2).
- Physical correlation between latest-slot replacements and decoder/network load is Pending.

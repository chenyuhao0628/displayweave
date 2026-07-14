[English](high-refresh-work-budget-audit.md) | [简体中文](high-refresh-work-budget-audit.zh-CN.md)

# High-refresh Work-budget Audit

Baseline: `79cbf90`; physical A/B validation: **Pending**.

`SendQueuePolicy` correctly evaluates `max(pendingSends, 0) + max(pendingEncodes, 0)` against the quality budget (Gaming 1, Low/Balanced 2, High 3). The drop occurs before encode and does not force a keyframe, so it does not break the encoded reference chain.

Findings:

- **WB-001 (P1): encode ownership is not generation-scoped.** `pendingEncodes` is one scalar. Encode callbacks carry `wireConnectionGeneration` for send rejection, but completion decrements the shared scalar before generation validation. Reconnect clears pending sends but not pending encodes. Delayed or missing callbacks can therefore hold a new session at budget; any future reset would allow old callbacks to decrement new work. Use per-encoder/wire-generation accounting.
- **WB-002 (P2): no peak or invariant telemetry.** Counts clamp at zero, hiding underflow attempts. Add peak values and debug assertions/counters for unmatched completions.
- **WB-003 (P2): local fast-decrease uses only queue-at-budget and rising oldest age.** `encodedFps`, `sentFps`, and `sendCompletionDelayMs` are validated and observed but are not control inputs. This is accurately documented here; no speculative control change is made without physical A/B data.
- **WB-004 (P2): budget optimality is unverified.** Source review cannot establish whether combined budgets over-drop at 60/90/120 fps. Defaults remain unchanged pending controlled device tests.

Drop semantics are correct for pre-encode skips. Stale encoded output is discarded after encode and does not enter the new connection, but because an encoded reference frame may have been omitted from the wire, recovery keyframe handling for every stale/post-encode discard must remain explicit.

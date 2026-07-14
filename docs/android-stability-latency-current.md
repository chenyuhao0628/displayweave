[English](android-stability-latency-current.md) | [简体中文](android-stability-latency-current.zh-CN.md)

# Android Stability and Latency — Current State

Current code baseline: `79cbf90` plus the local audit remediations documented in `current-code-audit-report.md`. The historical pre-implementation table remains in [the baseline audit](android-stability-latency-audit.md).

| Area | Current status | Evidence | Physical validation |
| --- | --- | --- | --- |
| Connection generation / independent accept loop | Implemented | immutable transport contexts, current-generation coordinator, takeover self-tests | Pending |
| Session epoch / config version / frame sequence | Implemented for negotiated V2; Legacy fallback retained | protocol-session filtering and self-tests | Pending |
| StreamConfig Ack / Decoder Ready / First Frame Rendered | Implemented for V2 | typed messages and identity checks | Pending |
| Frame-size negotiation | Implemented: Legacy 1 MiB, V2 default 8 MiB, absolute 16 MiB | protocol tests and transport loopbacks | Pending |
| Async MediaCodec | Implemented with local callback-generation, input ownership, bounded telemetry, and terminal recovery remediation | deterministic callback-state tests; Android build passes | Pending |
| Reference-chain recovery | Implemented for H.264 IDR and HEVC IRAP 16–23; dependent frames rejected after a break | classifier and callback-state self-tests | Pending |
| Decoder low latency / WiFi lock / Surface frame rate | Implemented with modes and lifecycle telemetry | policy/lifecycle tests | Pending |
| Drop attribution / ABR filtering | Implemented; recovery drops excluded from congestion totals | Drop tracker and ABR tests | Pending |
| Combined Mac work budget | Implemented; local audit adds encoder-generation ownership | SendQueue and generation-counter tests; macOS build passes | Pending A/B at 60/90/120 |
| Binary Frame Header V2 | Implemented only after full capability negotiation | malformed-input, capability-gating, and byte-for-byte Legacy tests | Protocol verified; runtime Pending |
| Thermal/power and allocation/GC metrics | Implemented; GC fields now represent per-window deltas | metric self-tests | Pending correlation |
| Frame buffer pool | Not implemented by design | ownership design only | Not applicable |

No physical performance, recovery-time, or compatibility claim is made without the device matrix in `current-physical-validation-matrix.md`.


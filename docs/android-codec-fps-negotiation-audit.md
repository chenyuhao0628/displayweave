[English](android-codec-fps-negotiation-audit.md) | [简体中文](android-codec-fps-negotiation-audit.zh-CN.md)

# Android Codec/FPS Negotiation Audit

Baseline: `79cbf90`; physical validation: **Pending**.

- **FPS-001 (P1, locally fixed): advertised cap was not bound to runtime candidate order.** Capability selection now uses the same acceleration/low-latency ordering as the default runtime decoder policy and evaluates the named selected candidate rather than returning during raw enumeration.
- **FPS-002 (P1, locally fixed conservatively): codec fallback did not preserve the advertised cap.** When HEVC is preferred, the advertised maximum is now the minimum supported by the selected HEVC and selected H.264 fallback candidates, so fallback cannot retain a HEVC-only FPS promise.
- **FPS-003 (implemented; physical matrix pending):** `DecoderRuntimeInfo` and `decoderConfigured` now report the selected decoder/max FPS. `MacSender.applySelectedDecoderFpsCap` applies a strictly lower operating point and resends stream configuration; it does not oscillate upward. Vendor capability/rotation behavior still needs device evidence. See [runtime recovery](android-decoder-throughput-recovery.md).
- Width/height: the advertised dimensions use the current window bounds after display-profile scaling, with even alignment. Orientation changes recalculate the `DisplaySpec`; physical rotation behavior remains Pending.
- Refresh mapping: `RefreshRateController` correctly selects the smallest valid mode at or above the requested bucket. Tests cover 90→120 and 120→165 fallback. 59.94 is bucketed to 60. The Surface request is kept distinct from reported actual display Hz in Mac telemetry.

The source already carries named decoder limits and runtime downgrade feedback. Keep advertised limits, observed throughput and rendered FPS distinct; this dated audit no longer treats the handshake as unimplemented.

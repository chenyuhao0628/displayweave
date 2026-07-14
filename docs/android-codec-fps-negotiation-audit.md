[English](android-codec-fps-negotiation-audit.md) | [简体中文](android-codec-fps-negotiation-audit.zh-CN.md)

# Android Codec/FPS Negotiation Audit

Baseline: `79cbf90`; physical validation: **Pending**.

- **FPS-001 (P1, locally fixed): advertised cap was not bound to runtime candidate order.** Capability selection now uses the same acceleration/low-latency ordering as the default runtime decoder policy and evaluates the named selected candidate rather than returning during raw enumeration.
- **FPS-002 (P1, locally fixed conservatively): codec fallback did not preserve the advertised cap.** When HEVC is preferred, the advertised maximum is now the minimum supported by the selected HEVC and selected H.264 fallback candidates, so fallback cannot retain a HEVC-only FPS promise.
- **FPS-003 (P2, physical Pending): vendor-reported support still needs runtime feedback.** Configure/runtime failure can move beyond the statically selected candidate; selected decoder name is reported after configuration, but selected decoder max FPS and a runtime FPS downgrade handshake are not yet published. This remains a measured-device follow-up rather than a claimed capability.
- Width/height: the advertised dimensions use the current window bounds after display-profile scaling, with even alignment. Orientation changes recalculate the `DisplaySpec`; physical rotation behavior remains Pending.
- Refresh mapping: `RefreshRateController` correctly selects the smallest valid mode at or above the requested bucket. Tests cover 90→120 and 120→165 fallback. 59.94 is bucketed to 60. The Surface request is kept distinct from reported actual display Hz in Mac telemetry.

Recommended design: select a named decoder capability record per codec and size, advertise codec-specific limits, carry the selected decoder name/max FPS into runtime metrics, and renegotiate StreamConfig after codec fallback or size/orientation changes.

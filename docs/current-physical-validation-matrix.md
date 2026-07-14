[English](current-physical-validation-matrix.md) | [简体中文](current-physical-validation-matrix.zh-CN.md)

# Current Physical Validation Matrix

Status captured 2026-07-15: `adb devices -l` returned no attached devices. No runtime result is inferred from source or automated tests.

| Transport | Codec | FPS | Status |
| --- | --- | --- | --- |
| WiFi | H.264 | 60 | Pending |
| WiFi | HEVC | 60 | Pending |
| WiFi | HEVC | 90/120 when supported | Pending |
| USB | H.264 | 60 | Pending |
| USB | HEVC | 60 | Pending |
| USB | HEVC | 90/120 when supported | Pending |

All recovery scenarios (USB removal/reinsert, rapid cycling, ADB restart/authorization, background/foreground, lock/unlock, Surface rebuild, WiFi recovery, Auto transport switching, codec fallback, repeated reconnect, and half-open socket takeover) are Pending.

Each future matrix cell requires 30 seconds warm-up, two runs of at least three minutes, one primary variable changed per comparison, and the metrics listed in the audit task brief. Legacy iOS/old Android physical compatibility is also Pending; only protocol-level compatibility may be reported until those builds are exercised.

[English](android-quick-recovery-v2.md) | [简体中文](android-quick-recovery-v2.zh-CN.md)

# Android quick recovery V2 evidence

## Modified files

- This evidence matrix consolidates the implemented connection-generation, Protocol V2, keyframe, frame-size, decoder, transport, and recovery controls.
- It supersedes the shorter generic checklist for the current Android stability/latency build.

## Purpose

Define the exact short physical recovery run and separate code/test evidence from device evidence. This document does not claim endurance or long-term stability.

## Required result for every scenario

- status is explicit and recovery is bounded;
- no stale connection updates UI, releases the current decoder, or contributes frames;
- no duplicate session, residual ADB forward, persistent black screen, or unbounded queue/retry loop;
- StreamConfig Ack, Decoder Ready, First Frame, reconnect time, and time to first frame are recordable where Protocol V2 is negotiated.

## Evidence matrix

| Scenario | Code/self-test evidence | Physical result |
| --- | --- | --- |
| USB unplug / replug | generation replacement, bounded transport recovery, stale callback guards | Pending — no device attached |
| ADB server restart | forward reconciliation and bounded retry policies covered | Pending — no device attached |
| Revoke / restore USB authorization | explicit authorization state and finite recovery path | Pending — no device attached |
| Android background / foreground | Surface and receiver lifecycle self-tests pass | Pending — no device attached |
| Android lock / unlock | Surface recreation path covered | Pending — no device attached |
| Brief WiFi loss / restore | watchdog and reconnect state machine are bounded | Pending — no device attached |
| Auto USB → WiFi | install identity and single-current-session policy implemented | Pending — no device attached |
| Auto WiFi → USB | new generation replaces old before streaming | Pending — no device attached |
| HEVC → H.264 fallback | config resend plus coalesced forced keyframe implemented | Pending — no device attached |
| Manual reconnect | fresh generation/session identity and keyframe implemented | Pending — no device attached |
| Rapid repeated reconnect | old disconnect ignored; only current generation mutates state | Pending — no device attached |
| Half-open old connection / immediate takeover | accept loop and connection-generation takeover self-test passes | Pending — no device attached |

## Test procedure

For each available scenario: warm up 30 seconds, record for 3 minutes, and repeat at least twice (three times when practical). Capture transport, codec, requested FPS, actual display Hz, rendered FPS average/1% low, frame-age P50/P95/P99, RTT P50/P95, bitrate, queues, classified drops, keyframe count/peak size, reconnect time, time to first frame, decoder reset count, black-screen count, thermal/power metrics, and visual notes.

Change only one major variable per comparison. Preserve failed samples. Stop on unsafe thermal state, sustained frame-age growth, or an unbounded/repeating recovery symptom.

## Tests

- Android clean/test/assemble and all receiver self-test groups cover the non-physical state-machine contracts.
- Standalone Mac tests cover transport selection, ADB forward handling, keyframe requests, queue policy, and capability fallback.
- Physical actions cannot be truthfully replaced with mocks or source inspection.

## Build result

Android clean/test/Debug assembly (`61 actionable tasks` and all six self-test groups), all 22 standalone Swift tests, Xcode generation, unsigned macOS/iOS Simulator builds, the production site, 34 bilingual pairs, release links, and diff checks passed. `adb devices -l` returned no attached device during this audit.

## Before/after metrics

No physical before/after recovery timing is available. The matrix records only verified software contracts and leaves all device outcomes pending.

## Known risks

- Vendor USB authorization, ADB daemon, WiFi, Surface, and codec behavior require real hardware.
- Legacy iOS compatibility requires an actual older receiver build in addition to byte-for-byte framing tests.
- Passing short recovery runs would not establish 30-minute or 2-hour endurance.

## Pending physical validation

All twelve scenarios above remain pending. Also run WiFi and USB HEVC at 60/120 FPS when the connected panel and decoder genuinely support those modes.

## Next step

Attach the available Android receiver, run the matrix, and append raw run IDs and observations without rewriting pending entries as success unless the evidence exists.

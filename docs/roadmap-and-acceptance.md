[English](roadmap-and-acceptance.md) | [简体中文](roadmap-and-acceptance.zh-CN.md)

# Development and acceptance

The [roadmap](../ROADMAP.md) and [feature ledger](feature-completion.md) record implementation and verification for v0.3.0-preview.1 (16). Encrypted pairing, Apple high refresh, Mac input/handover, advanced Pencil and protocol fixtures are included. Production identities and approved final artwork remain external requirements; physical performance has its own acceptance gate.

## Automated source gate

Run the full [development gate](development.md), including production-code TLS/Keychain/Keystore fixtures, negative authentication cases, shared protocol vectors, ownership/cancellation, all platform builds, Android Lint, website/docs/release checks, packaging tests and brand-export checks. Simulator results are recorded separately from physical performance. Hosted Actions unavailability must not be reported as a passing check.

## Physical matrix

- Mac: both sender/receiver directions; mirror/extend and all desktop modes; Wi-Fi/Ethernet/direct-link handover; sleep/wake/hotplug; Intel/Apple silicon; focused input and emergency release.
- Apple receivers: hardware HEVC/H.264 fallback, requested versus actual refresh, Pencil pressure/tilt/roll/eraser/double-tap/squeeze and drawing-app shortcut mapping.
- Android: paired LAN and ADB USB, manufacturer decoder/fallback and throughput cap, allocation/GC measurements, two simultaneous receivers and independently owned forwards.
- Transport: matched resolution/codec/bitrate/temperature USB-versus-Wi-Fi; 30-minute and two-hour runs; thermal, memory, reconnect and retained-resource evidence.
- UI/brand: physical launcher/Dock, light/dark and small sizes, keyboard navigation and mobile rotation/Dynamic Type.

Earlier Preview 2 evidence covers one OnePlus USB HEVC/120 and H.264/60 path, touch/scroll, unplug/ADB/authorization recovery and one iPhone/Android concurrent session. One reported Wi-Fi run rendered about 109–111fps at a requested 120fps. It does not prove sustained 120fps, new TLS performance, all hardware, or two Android receivers.

Promote a feature to physically verified only with device/OS, source commit, exact settings, duration, actual rendered metrics, failure/recovery results and matching English/Chinese evidence. Never create a virtual display without an independent online display; record SKIP and continue noninteractive checks.

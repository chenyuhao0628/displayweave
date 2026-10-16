[English](ROADMAP.md) | [简体中文](ROADMAP.zh-CN.md)

# DisplayWeave Roadmap

## Packaged in v0.2.1-p7 — 2026-10-16

- Exclusive Mac sender/receiver roles for one-way LAN mirror/extend.
- Shared UI standard and Mac/iOS/Android/web refactor; accessible receiver settings and responsive bilingual navigation.
- Selected upstream startup recovery, bounded logs and two-finger click suppression.
- Shared Apple frame/cursor bounds, lifecycle isolation, safe input/geometry conversion and Android control backpressure.
- Hardware-gated Mac HEVC, interface-pinned direct-link candidates and negotiated Pencil pressure/tilt/proximity.
- 37 Swift suites and platform compatibility builds. See the [current feature guide/evidence](docs/hevc-wired-pencil.md) and [prior source audit](docs/source-upgrade-audit-2026-10-16.md) for exact results and physical gaps.

v0.2.1-p7 packages these changes as a development preview. The new hardware-dependent features remain experimental until the physical acceptance below is complete.

## Shipped and verified in Preview 2

- Android per-device dynamic ADB-forward USB.
- Auto USB preference, bounded recovery, same-install-ID WiFi fallback, and USB upgrade.
- Android foreground/surface reconnect and stream configuration restoration.
- Android HEVC/120 and H.264/60 USB paths on the available OnePlus device.
- Cable, ADB restart, authorization revoke/reallow, touch, and two-finger scroll checks.
- Offline v2-signed Android APK and mixed current-iPhone/Android concurrency.
- Short benchmark recording, target/actual bitrate separation, Auto/Manual/Benchmark modes, adaptive bitrate, bounded send queues, and transport-aware keyframes (automated verification; physical performance matrix pending).

## Next validation

Validate HEVC/fallback on Intel and Apple silicon, Thunderbolt Bridge/Ethernet routing with Wi-Fi enabled, and real Pencil pressure/hover/palm rejection. First complete two-Mac acceptance in both directions, mirror/extend, Wi-Fi/Ethernet, sleep/wake, display hotplug and Intel runtime. Repeat Mac UI and virtual-display cleanup with an independent online display; complete Android visual and mobile real-input acceptance.

1. Two simultaneous Android receivers with independent serials, ports, cleanup, input, and reconnect.
2. Controlled same-resolution/codec/bitrate USB versus WiFi benchmark.
3. Maintainer-run 30-minute and 2-hour endurance checks with thermal, memory, reconnect, and forward-leak evidence.
4. Broader Android SoC, macOS version, cable, and network matrix.

## Product work

- Encrypted WiFi pairing and authenticated sessions.
- iOS/iPadOS high-refresh path and broader Apple-device validation.
- Stable public protocol versioning and compatibility tests.
- Developer ID signing/notarization and normal iOS distribution when paid identities become available.
- Final transparent/light/dark brand masters and platform-adaptive icons.

High-refresh targets remain experimental until sustained rendered-frame evidence passes defined acceptance thresholds. See [docs/roadmap-and-acceptance.md](docs/roadmap-and-acceptance.md).

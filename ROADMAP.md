[English](ROADMAP.md) | [简体中文](ROADMAP.zh-CN.md)

# DisplayWeave Roadmap

## Shipped and verified in Preview 2

- Android per-device dynamic ADB-forward USB.
- Auto USB preference, bounded recovery, same-install-ID WiFi fallback, and USB upgrade.
- Android foreground/surface reconnect and stream configuration restoration.
- Android HEVC/120 and H.264/60 USB paths on the available OnePlus device.
- Cable, ADB restart, authorization revoke/reallow, touch, and two-finger scroll checks.
- Offline v2-signed Android APK and mixed current-iPhone/Android concurrency.

## Next validation

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

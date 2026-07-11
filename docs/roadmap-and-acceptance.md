[English](roadmap-and-acceptance.md) | [简体中文](roadmap-and-acceptance.zh-CN.md)

# DisplayWeave Development and Acceptance Targets

## Verified in Preview 2

- Android per-serial dynamic ADB-forward USB and exact mapping cleanup.
- Auto wired preference, bounded recovery, same-install-ID WiFi fallback, and atomic USB upgrade.
- Android foreground/surface reconnect and `streamConfig` restoration.
- OnePlus USB HEVC/120 and H.264/60; touch and two-finger scroll.
- Cable unplug/replug, ADB restart, authorization revoke/reallow, and receiver reopen recovery.
- Offline v2-signed Android APK and one current iPhone/one Android concurrent session.

## Experimental

- Android 30/60/90/120fps high refresh. OnePlus HEVC/120 WiFi measured about 109–111 rendered FPS; stable 120 FPS is not promised.
- Private macOS `CGVirtualDisplay` behavior.
- Local WiFi transport pending encrypted pairing.

## Deferred acceptance

- Two Android receivers concurrently with independent serials, ports, input, cleanup, and reconnect.
- Controlled same-resolution/codec/bitrate/temperature USB versus WiFi benchmark.
- 30-minute and 2-hour endurance tests with thermal, memory, drop, reconnect, and forward-leak evidence.
- iOS/iPadOS 120Hz and production signing/distribution.

Moving an item to verified requires reproducible builds, named hardware and OS, exact settings, passing automated checks, recovery evidence, relevant performance metrics, and synchronized English/Chinese documentation.

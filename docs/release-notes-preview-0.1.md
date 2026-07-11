[English](release-notes-preview-0.1.md) | [简体中文](release-notes-preview-0.1.zh-CN.md)

# DisplayWeave `v0.1.0-preview.2` Release Notes

Preview 2 turns the Android USB path from an implementation claim into a physically validated development preview and publishes independently packaged Mac, Android, and iOS re-signing inputs.

## Highlights

- Android USB uses one dynamic Mac-local `adb forward` per wired serial.
- Auto prefers USB, runs bounded recovery, falls back only to the same install ID over WiFi, and upgrades back to USB without allowing two sessions to contest the Android receiver.
- Wireless-debugging ADB endpoints cannot create false USB sessions.
- Android surface/foreground return, stream configuration restoration, and protocol-level reconnect readiness are fixed.
- OnePlus HEVC/120 and H.264/60 USB paths, touch, two-finger scroll, cable unplug/replug, ADB restart, authorization revoke/reallow, and WiFi fallback were verified.
- One current DisplayWeave iPhone WiFi receiver and one Android receiver ran concurrently.
- Android is distributed as an offline v2-signed release APK.

## Assets

- `DisplayWeave-Preview-0.1-macOS.zip` — universal ad-hoc signed; not Developer ID signed or notarized.
- `DisplayWeave-Preview-0.1-Android.apk` — offline project-signed release APK.
- `DisplayWeave-Preview-0.1-iOS-unsigned-resigning-input.ipa` — unsigned input; cannot be installed directly.
- `SHA256SUMS.txt` — SHA-256 verification for all packages.

## Evidence boundaries

The available OnePlus HEVC/120 WiFi result remains about 109–111 rendered FPS and does not guarantee stable 120 FPS. Two simultaneous Android devices, controlled same-condition USB/WiFi benchmarking, and 30-minute/2-hour endurance tests are deferred. Current WiFi TCP is not production-encrypted; use a trusted LAN.

See [release checklist](release-checklist.md) and [stability report](stability-test-report.md).

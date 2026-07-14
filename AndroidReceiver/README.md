[English](README.md) | [简体中文](README.zh-CN.md)

# DisplayWeave Android Receiver

The Android receiver accepts DisplayWeave video over local WiFi or a Mac-managed ADB-forward USB connection. It negotiates HEVC/H.265 or H.264, requests 30/60/90/120Hz-compatible modes, renders through MediaCodec/Surface, and returns touch/input plus pipeline metrics.

## Requirements

- Android 8.0+; hardware HEVC support is device-dependent.
- WiFi: Mac and Android on the same trusted LAN with Nearby WiFi/Local Network discovery permission where required.
- USB: a data-capable cable, Developer options, USB debugging, and approval of the Mac's RSA identity.

## Install `v0.2.1`

Download `DisplayWeave-Android.apk` from [`v0.2.1`](https://github.com/chenyuhao0628/displayweave/releases/tag/v0.2.1). It is an offline v2-signed release APK and does not require Google Play. Install it over the existing `app.opendisplay.android` package once. Verify `SHA256SUMS.txt` and the certificate fingerprint in [the release checklist](../docs/release-checklist.md) before installing.

## Updates after the first install

- The receiver checks the HTTPS update feed at most once per 24 hours when it resumes.
- **Settings & Help → Check for Updates** bypasses the daily throttle.
- Before installation, it verifies exact byte count, SHA-256, package name,
  version code, minimum SDK, and the pinned signing certificate.
- Android may ask for permission to install unknown apps. The final installation
  always uses Android's system confirmation UI; silent installation is not supported.
- Declining the permission or installation does not stop the display receiver.

## Connect

1. Open DisplayWeave Receiver and leave its display surface visible.
2. On the Mac choose **Auto** (recommended), **USB**, or **WiFi**.
3. For USB, connect the cable and accept the Android RSA dialog. Only the wired ADB row is eligible; wireless-debugging ADB endpoints are ignored.
4. Auto prefers USB. After a real failure it uses protocol grace and bounded recovery, then may fall back only to WiFi with the same install ID. Cable return upgrades the session back to USB.
5. Returning to the receiver after the Android desktop recreates the surface and restarts the listener idempotently; the Mac resends `streamConfig` before requesting a keyframe.

USB mode never silently becomes WiFi. WiFi mode never creates an ADB forward.

## Decoder low latency

**Settings & Help → Decoder Low Latency** defaults to Auto. Auto/On requests MediaCodec low latency only when the actual API 30+ decoder advertises support; a rejected parameter is retried on the same decoder without low latency. Off never sets the parameter. Changing this setting rebuilds the receiver session once. See [the decoder low-latency policy](../docs/android-decoder-low-latency.md).

## WiFi and display latency hints

**Settings & Help → WiFi Low Latency** defaults to Auto. On API 29+, Auto/On holds `WIFI_MODE_FULL_LOW_LATENCY` only while the app is foreground, the Surface is valid, video is Streaming, and the actual Mac transport is WiFi. USB, disconnect, background, Surface loss, and app exit release it. The Surface frame-rate hint uses fixed-source and only-if-seamless behavior, is reapplied for Surface/config/decoder lifecycle events, and is cleared when streaming stops. See [WiFi low latency and Surface frame rate](../docs/android-wifi-low-latency-surface-frame-rate.md).

## Drop attribution

Receiver stats retain the aggregate Android drop count and also publish per-reason window/lifetime counts plus the last drop's connection/config/frame identity. Auto bitrate ignores lifecycle, stale, malformed, transport, and reconfiguration drops; classified decoder-throughput pressure must persist for two windows before it can lower bitrate. See [the Android drop-reason policy](../docs/android-drop-reason-policy.md).

## Build and test

```bash
cd AndroidReceiver
./gradlew clean test assembleDebug
```

Debug APK:

```text
app/build/outputs/apk/debug/app-debug.apk
```

Release packaging and signing are orchestrated from the repository root:

```bash
./tools/package-preview-0.1.sh
```

The keystore remains outside Git; its password is read from macOS Keychain. Do not generate a replacement key for an existing public package identity unless you intentionally break upgrade compatibility.

## Protocol and lifecycle

- Receiver TCP server: Android port `9000`.
- USB: Mac `127.0.0.1:<dynamic>` → `adb forward` → Android `tcp:9000`.
- WiFi: Mac connects directly to the advertised LAN address.
- Video: length-prefixed frames with `streamConfig`; HEVC preferred when supported, H.264 fallback on capability/codec failure.
- Input: tap, drag, cursor, and two-finger scroll JSON.
- Recovery: listener/surface operations are idempotent; readiness requires a peer protocol message rather than TCP connect alone.

## Prior verified Preview 2 behavior

- OnePlus HEVC/120 and H.264/60 over USB.
- Foreground return, force-stop/reopen, ADB server restart, cable unplug/replug, and authorization revoke/reallow recovery.
- Auto USB→same-install-ID WiFi fallback observed after the complete recovery sequence, about 26 seconds in that run; USB upgrade on cable return.
- Touch and two-finger scrolling over USB.
- One current iPhone WiFi session and one Android session concurrently.

Two simultaneous Android devices, controlled USB/WiFi benchmark, and 30-minute/2-hour endurance runs remain incomplete.

## Security

WiFi TCP is not production-encrypted. Use a trusted LAN. ADB authorization trusts the Mac as a debugging host beyond this application. See [SECURITY.md](../SECURITY.md).

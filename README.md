[English](README.md) | [简体中文](README.zh-CN.md)

# DisplayWeave

**One Mac. A woven field of useful screens.**

DisplayWeave is an independently maintained, GPL-3.0, local-first second-display project derived from [OpenDisplay](https://github.com/peetzweg/opendisplay). It turns iPhone, iPad, and Android devices into extended or mirrored displays for a Mac.

## Preview 2 capabilities

- Apple receivers: USB through `usbmuxd` and local WiFi, using the H.264 path.
- Android receiver: local WiFi or per-device dynamic `adb forward` USB, HEVC/H.265 with H.264 fallback, and 30/60/90/120fps negotiation.
- Transport selector: Auto, USB, or WiFi. Auto prefers wired USB, performs bounded recovery, falls back only to WiFi with the same install ID, and upgrades back to USB when the cable returns.
- Input: tap, drag, cursor, and two-finger scrolling return to macOS.
- Recovery: receiver foreground/surface return, cable unplug/replug, ADB restart, and authorization revoke/reallow were verified on the available OnePlus Android device.
- Mixed receivers: one current DisplayWeave iPhone over WiFi and one Android receiver ran concurrently.
- Runtime evidence: capture, encode, send, receive, decode, render, queue, drop, and latency metrics.

Android high refresh remains experimental. One OnePlus HEVC/120 WiFi run measured about 109–111 rendered FPS; this does not guarantee stable 120 FPS on other devices or conditions.

## Download `v0.1.0-preview.2`

[GitHub Release](https://github.com/chenyuhao0628/displayweave/releases/tag/v0.1.0-preview.2)

| Platform | Asset | Distribution boundary |
| --- | --- | --- |
| macOS | `DisplayWeave-Preview-0.1-macOS.zip` | Universal ad-hoc signed app; not Developer ID signed or notarized |
| Android | `DisplayWeave-Preview-0.1-Android.apk` | Offline release APK, v2-signed with the project Preview key; no Google Play account required |
| iOS/iPadOS | `DisplayWeave-Preview-0.1-iOS-unsigned-resigning-input.ipa` | Unsigned re-signing input; cannot be installed directly |
| Verification | `SHA256SUMS.txt` | SHA-256 for all three packages |

This is a development preview, not a production-signed store release. Verify the checksum before use. Android users should also compare the certificate fingerprint in the [release checklist](docs/release-checklist.md).

## Android USB quick start

1. Enable Developer options and USB debugging on the Android device.
2. Connect a data-capable cable, open DisplayWeave Receiver, and allow the Mac's RSA debugging identity.
3. Open DisplayWeave on the Mac and choose **Auto** (recommended) or **USB**.
4. Auto uses only a true wired `usb:` ADB device. Wireless-debugging endpoints never create a USB session.
5. If the cable is removed, Auto completes protocol grace and bounded recovery before falling back to the same app installation over WiFi. USB mode does not silently fall back.

ADB authorization grants the Mac broad debugging access, not only DisplayWeave access. Revoke it in Android Developer options when it is no longer needed.

## Build from source

Apple targets:

```bash
./generate.sh
xcodebuild -project OpenSidecar.xcodeproj -scheme OpenSidecarMac \
  -configuration Debug -derivedDataPath build-run \
  -clonedSourcePackagesDirPath build-run/SourcePackages build
```

Android:

```bash
cd AndroidReceiver
./gradlew clean test assembleDebug
```

Create the complete offline Preview package set:

```bash
./tools/package-preview-0.1.sh
```

Android release signing uses a keystore stored outside the repository. See [development preview distribution](docs/development-preview.md).

## Documentation

- [Documentation index](docs/README.md)
- [Architecture](ARCHITECTURE.md)
- [Roadmap](ROADMAP.md)
- [Android receiver](AndroidReceiver/README.md)
- [Release checklist](docs/release-checklist.md)
- [Stability evidence](docs/stability-test-report.md)
- [USB/WiFi benchmark protocol](docs/usb-vs-wifi-benchmark.md)
- [Security policy](SECURITY.md)
- [Contributing](CONTRIBUTING.md)
- [Third-party notices](THIRD_PARTY_NOTICES.md)

## Current limits

- iOS/iPadOS 120Hz is not implemented.
- Current WiFi TCP video/control traffic is not production-encrypted; use a trusted LAN.
- Two simultaneous Android devices, the controlled same-condition USB/WiFi benchmark, and 30-minute/2-hour endurance runs remain incomplete.
- macOS uses private `CGVirtualDisplay` behavior that may change in future macOS versions.
- Public macOS and iOS packages are not Developer ID/App Store signed.

## Origin and license

DisplayWeave preserves the applicable OpenDisplay history, copyright notices, and GPL-3.0 obligations. Some high-refresh and measurement approaches were informed by the MIT-licensed SideScreen project. See [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md). DisplayWeave itself is distributed under [GPL-3.0](LICENSE).

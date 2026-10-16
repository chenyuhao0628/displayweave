[English](release-notes-v0.2.1-p7.md) | [简体中文](release-notes-v0.2.1-p7.zh-CN.md)

# DisplayWeave `v0.2.1-p7` release notes

Version `0.2.1-p7`, Mac build / Android version code `14`. This development preview packages the reviewed Mac-to-Mac, UI and input work from PRs #11 and #12. New hardware-dependent features remain experimental.

## Changes

- Either Mac can send or receive a one-way extended or mirrored desktop over Wi-Fi or Ethernet; both require macOS 14+. Sender and receiver roles are exclusive.
- Mac video negotiates hardware HEVC with H.264 fallback, conservative resolution limits and at most 60 fps. Fallback persists across reconfiguration on the same connection.
- Link-local wired Mac discovery identifies direct-link candidates and pins Bonjour/TCP to their interface. Auto-connect is off by default. An ordinary USB-C cable is not proof of a working Mac network; no remote shutdown is included.
- iPad Pencil input negotiates pressure, tilt and supported hover, with palm suppression, bounded input queues and deterministic cancellation. Old senders retain whole-stroke touch compatibility. iOS video remains H.264.
- Mac, iOS, Android and website UI use shared guidelines; receiver settings, navigation and failure/retry states were improved.
- Session cleanup, stale callbacks, frame/cursor bounds, log limits and Android input backpressure were hardened. USB/LAN mode changes now exclude disallowed reconnects.

Quality changes encoded scaling (50% / 75% / 100%, Smooth 75%) by rebuilding sessions; it does not add a per-device fixed 1080p/1440p/4K desktop mode picker.

## Verification and remaining acceptance

The source passed 37 Swift suites, Mac arm64/x86_64 builds, iOS Simulator build, Android tests/build, website and bilingual-documentation checks. The release workflow separately builds and verifies the distributable packages, Android signer and update metadata. Exact release artifact hashes and workflow evidence are recorded after packaging.

Two-Mac physical routing/performance, real Pencil pressure/tilt/hover/palm rejection, new UIKit gesture runtime, Intel runtime, and 30-minute/2-hour endurance acceptance remain pending. The host had no verified independent display, so virtual-display interaction was skipped. Automated checks and encoded-sample parsing do not establish measured on-screen performance. See the [feature guide](hevc-wired-pencil.md).

## Distribution and upgrade

The seven assets remain the Mac DMG and Sparkle ZIP, Android APK, unsigned iOS re-signing input, `appcast.xml`, `android-update.json`, and `SHA256SUMS.txt`. Mac packages remain ad-hoc signed and not notarized; the APK retains the pinned project certificate; the iOS IPA requires personal re-signing before installation. Existing application IDs and update public keys are preserved.

Android p6 and later use Cloudflare first with GitHub availability fallback. Android p5 and older require a manual install to trust the mirror. Existing supported Mac/Android installations can use their update channel after publication.

[GitHub Release](https://github.com/chenyuhao0628/displayweave/releases/tag/v0.2.1-p7)

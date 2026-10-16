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

The source passed 37 Swift suites, Mac arm64/x86_64 builds, iOS Simulator build, Android tests/build, website and bilingual-documentation checks. The release workflow separately builds and verifies the distributable packages, Android signer and update metadata. Release run [38839071173](https://github.com/chenyuhao0628/displayweave/actions/runs/38839071173) succeeded at tag commit `e56250c4539dcd8449508265401b4f28dddf1ccd`. Its feed-deployment job was intentionally skipped while staging the mirror. Downloaded assets independently passed `verify-update-release.sh`: Mac DMG/ZIP identity and signature match, Android version/certificate and all six checksums. The Mac executable contains arm64 and x86_64, the iOS input is unsigned arm64, and both report `0.2.1-p7 (14)`. CryptoKit independently verified the ZIP Ed25519 signature against the embedded Sparkle public key.

Two-Mac physical routing/performance, real Pencil pressure/tilt/hover/palm rejection, new UIKit gesture runtime, Intel runtime, and 30-minute/2-hour endurance acceptance remain pending. The host had no verified independent display, so virtual-display interaction was skipped. Automated checks and encoded-sample parsing do not establish measured on-screen performance. See the [feature guide](hevc-wired-pencil.md).

## Distribution and upgrade

The seven assets remain the Mac DMG and Sparkle ZIP, Android APK, unsigned iOS re-signing input, `appcast.xml`, `android-update.json`, and `SHA256SUMS.txt`. Mac packages remain ad-hoc signed and not notarized; the APK retains the pinned project certificate; the iOS IPA requires personal re-signing before installation. Existing application IDs and update public keys are preserved.

Android p6 and later use Cloudflare first with GitHub availability fallback. Android p5 and older require a manual install to trust the mirror. Existing supported Mac/Android installations can use their update channel after publication.

[GitHub Release](https://github.com/chenyuhao0628/displayweave/releases/tag/v0.2.1-p7)

## Artifact integrity

| Asset | SHA-256 |
| --- | --- |
| `DisplayWeave-Android.apk` | `ac1b5081259647c248e8c5d69aff4f477f4ebc9044a70c4a4602f6c81d6c2381` |
| `DisplayWeave-macOS.zip` | `dae40c3df8f9bbdebdce0484621a7d7a6a4c99c1b1a8504e9096fc8863705aef` |
| `DisplayWeave-macOS.dmg` | `26e9cf259410e731acfbe1a682444b71bf73d679298db6b00d82b3bef15ce0f6` |
| `DisplayWeave-Preview-0.1-iOS-unsigned-resigning-input.ipa` | `634305344f5cd7433a74a95166f781ea7313d5473ded88918528a3895e8eb1eb` |
| `appcast.xml` | `6b56809092184de9bc4043667f4e6fc9e0b293e8689b1e9c1c67c9be2c30a8b1` |
| `android-update.json` | `3486c40d0a72cb3fc4acdfedcbe2299d01f90bdd67432f8a32003e24d3091a50` |

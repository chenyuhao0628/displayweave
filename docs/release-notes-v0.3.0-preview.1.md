[English](release-notes-v0.3.0-preview.1.md) | [简体中文](release-notes-v0.3.0-preview.1.zh-CN.md)

# DisplayWeave `v0.3.0-preview.1` release notes

Version `0.3.0-preview.1`, Mac build / Android version code **16**, built locally on 2026-10-16. The native build source is `53d2dfa`; the release tag adds documentation, website copy and exact update feeds without changing native code or packaging inputs. The corresponding tagged source archive includes GPL-3.0, upstream notices and build scripts.

## Changes

- Native/1080p/1440p/4K extension desktop resolution saved per receiver; mirroring keeps the physical source geometry.
- Default certificate-pinned mutual TLS on Apple and Android, two-minute invitation pairing, retained trust, revocation and explicit insecure legacy compatibility.
- Hardware-gated Apple HEVC with H.264 fallback and bounded 30–120fps targets; requested FPS is not measured performance.
- Consented Mac receiver keyboard/mouse input and optional same-installation wired/Wi-Fi handover, with bounded work and session cleanup.
- Pencil roll/eraser and configurable double-tap/squeeze actions over authenticated connections; sender-owned shortcut mappings require separate permission.
- Process CPU metrics, bounded Android frame leases, shared protocol fixtures, adaptive Android icons and production Apple packaging preflight tools.
- iOS presentation ownership fix: late teardown of an old view cannot clear replacement callbacks or detach its video layer.

## Upgrade and pair

**Upgrade both sender and receiver.** On the receiver, open Security and pairing, generate an invitation, and import it on the sending Mac. LAN, ADB USB and Apple USB use the same authenticated stream. See [pairing](secure-transport.md), [resolution](desktop-resolution.md), [Mac input](mac-receiver-input.md) and [advanced Pencil](pencil-advanced.md).

Older applications require an explicit insecure legacy choice on the relevant new-app role and a trusted network. Authentication failure never falls back to plaintext. Peers with pairing history cannot silently downgrade. Saved application settings, package identifiers, Sparkle key and APK signing certificate remain compatible. This is a preview, not a claim of completed physical acceptance.

## Verification

Local gates passed: **52 Swift suites**, six Android Java groups, Android Debug/Release and Lint, universal Mac Debug/Release, iOS Simulator and unsigned arm64 device builds, website build, bilingual documentation and release checks. Actual Apple↔Java TLS, Mac/iOS Keychain and Android Keystore were exercised. Isolated iOS runtime covered encrypted video/Pencil, view replacement, revocation and background shutdown; isolated Android covered pairing/TLS/UI and adaptive-icon resolution. Twelve offline Apple packaging tests and 36 brand exports passed.

Package checks verified DMG/ZIP identity, deep Mac signatures, universal architectures, the existing Sparkle Ed25519 signature, the existing APK certificate/version/hash and the unsigned iOS boundary. The local Mac was replaced with build 16 before publication; its embedded feed and saved feed preference both point to the project GitHub Pages appcast. The previous installation is retained in a local backup outside Git.

Two-Mac physical routing/input, ProMotion/HEVC throughput, Pencil hardware/drawing-app behavior, Intel runtime, allocation/latency comparisons and 30-minute/2-hour endurance remain pending. Desktop capture and virtual-display interaction were skipped because no independent online display was verified. Simulator/synthetic checks do not prove physical performance. Production Apple signing identities and approved final editable brand masters remain external prerequisites.

## Distribution and integrity

Download from the [GitHub Release](https://github.com/chenyuhao0628/displayweave/releases/tag/v0.3.0-preview.1). All eight assets are on GitHub: four binaries, two feeds, `DisplayWeave-v0.3.0-preview.1-source.tar.gz` and `SHA256SUMS.txt`. The checksum manifest covers the other seven assets, including the matching source archive. Mac/Android metadata is hosted on the repository GitHub Pages site; no other download host or fallback is used.

Mac is ad-hoc signed and not notarized; first installation may require macOS approval. Android retains its signing identity for in-place installation. iOS is an unsigned re-signing input and requires a valid personal signing identity. The old p6/p7 draft records and p8 build records are not evidence of publicly available downloads.

| Asset | SHA-256 |
| --- | --- |
| `DisplayWeave-macOS.zip` | `c4cb42af68f0479d8fc884ae3c631655a24dca5ce5000ed9d2b3e81214e88cc7` |
| `DisplayWeave-macOS.dmg` | `820bad434a200cba3e7ef2d7acad0b3f052fcef6c479d57a1d8efb5bb1d5ac29` |
| `DisplayWeave-Android.apk` | `72e158c825f8ba16ac14677312167ee83a72aa6590b089c788dc54521c1b3057` |
| `DisplayWeave-Preview-0.1-iOS-unsigned-resigning-input.ipa` | `ba881f0c23e3a992ce0ca615ee245b8c638765b06e65dac0a9b3f913d51db965` |
| `appcast.xml` | `159a629e28cfb739479c86471ad521d967414e7835764a1e536e623cdcb73ce6` |
| `android-update.json` | `0a41d1c4635bf94803e946e3bad133172a7de319831daf9e0ab0c6ec8c3ee452` |

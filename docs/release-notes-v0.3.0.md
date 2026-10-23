[English](release-notes-v0.3.0.md) | [简体中文](release-notes-v0.3.0.zh-CN.md)

# DisplayWeave v0.3.0

Release date: 2026-10-23. **Stable release**, Mac build / Android version code **19**. Native source baseline: `929eb93`. This release includes the Mac 4K latency work and selectively reviewed upstream capture/display recovery. The previous release was v0.3.0-preview.3 (18).

## Changes

- At 60 FPS, allow two asynchronous encodes in flight, matching the existing 90/120 FPS allowance. Receiver backpressure tolerates short interruptions and recovers at a keyframe when necessary. All work remains bounded.
- Sample the sender's cursor independently every 8 ms, retain only the latest pending position, prioritize unsent cursor controls and coalesce receiver delivery. This reduces avoidable cursor delay without changing the wire format.
- Raise the H.264 LAN ceiling from 60 to **100 Mbps**, including Manual 80/100 Mbps. Ethernet and Wi-Fi share this policy. Auto adapts within bounds and restores its initial target after sustained uncongested activity; 4K60 High H.264 still starts near 49.77 Mbps. A 100 Mbps target is not measured throughput or a guarantee of smoother presentation.
- Retry encoder creation without low-latency mode when that mode is unsupported, retaining codec negotiation and hardware requirements. Creation/preparation failures now propagate to session cleanup and an actionable retry. A Mac receiver that never gets a usable first-video sample times out after 15 seconds instead of staying connected indefinitely.
- Replay the latest frame after capture drops; recover capture after sleep/lock and persistent wrong-source geometry. Bound retries, preserve per-device display placement, and recover owned virtual-display collisions in order. Retired sessions cannot modify their replacements.
- Record actual network interfaces, encoder mode, capture/encode/send rates, cursor delivery and receiver pressure; aggregate repeated errors. Diagnostic statistics do not include desktop pixels, key events or cursor coordinates.
- Publish neutral stable-release artifact names, including `DisplayWeave-iOS-unsigned-resigning-input.ipa`; update bilingual download and upgrade guides.

The [4K audit](mac-4k-latency.md) records local evidence. The [upstream integration record](upstream-integration-2026-10-23.md) maps each adaptation and test to its upstream commit, including three Mac fixes newer than upstream v1.26.0. GPL-3.0 and upstream attribution are retained.

## Upgrade and compatibility

Install this version on both Macs. Choose 4K for the extended desktop; mirror mode follows the source display. To request 100 Mbps, choose H.264 and **Manual → 100 Mbps**. Auto remains the default. A previously disabled low-latency preference stays disabled; the new fallback handles unsupported requests when enabled.

Mac uses the same pinned Apple Development identity as build 18. Packaging verified identity continuity against the downloaded build 18 app, including designated requirement, team, bundle ID and universal architectures. No installed app was replaced for this release, so build 18 → 19 privacy-permission continuity was not interactively retested. Earlier signed overwrite evidence remains in [Mac permissions](mac-permissions.md). The first move from an ad-hoc build may require authorization again.

**This stable release is not Developer ID signed or notarized.** On first installation, verify the checksum, place the app in `/Applications`, and use the documented **Privacy & Security → Open Anyway** recovery if macOS blocks it. Android keeps its pinned signing certificate. The iOS artifact remains unsigned and requires the user's own valid signing identity before device installation.

Bundle/package IDs, preferences, pairing records, Bonjour service, wire framing, Sparkle key, Android signing and USB/handover policies are preserved. Existing explicit OpenDisplay compatibility and DisplayWeave authenticated pairing remain available. Mac and Android updates use [the existing verified update channels](automatic-updates.md).

## Automated verification

- 60 standalone Swift suites; universal Mac Debug compilation for arm64 and x86_64; iOS Simulator Debug compilation.
- Signed universal Mac Release, guided DMG/ZIP content and nested-signature checks; unsigned arm64 iOS Release; Android tests, Debug/Lint and the signed Release APK.
- Actual Apple↔Java TLS, Mac/iOS Keychain persistence and recovery, isolated iOS TLS/video/lifecycle/Pencil checks, and Android Keystore/TLS/revocation/legacy-mode runtime checks.
- Two separately signed test binaries retained Keychain identity and pairing in an isolated namespace; 20 signing regressions, 12 distribution checks and 36 brand-asset checks passed.
- Independent Ed25519 verification of the ZIP against its embedded public key; feed URLs, versions, builds, lengths, hashes, iOS archive hygiene and the pinned Android certificate checked.
- Website production build, 96 bilingual-document pairs, release links and whitespace checks. The publication PR records hosted CI on the release commit separately from these local results.

Full logs remain under ignored `build/release-v0.3.0-audit/` and `build/diagnostics/upstream-review-2026-10-23/`. The earlier local arm64 synthetic 3840×2160 H.264 probe encoded 180/180 frames at approximately 60 FPS at both requested bitrate settings; it did not exercise a physical receiver or establish actual 100 Mbps traffic.

## Physical verification and deferred work

**SKIP:** Intel/macOS 15 runtime, two-iMac Ethernet presentation/latency, actual sleep/wake, multi-display recovery and sustained 4K60. Receiver-window and virtual-display fixtures were compiled but not run; no independent display session was established for interactive tests. No WindowServer or remote-access service was restarted.

Two-device LAN/USB comparison, Pencil hardware, two simultaneous Android receivers and 30-minute/2-hour endurance remain pending. Compilation, loopback traffic and synthetic policy tests do not establish those hardware results. The reported original black screen was associated with Screen Recording permission; H.264 itself was not established as its cause.

## Downloads

[GitHub Release](https://github.com/chenyuhao0628/displayweave/releases/tag/v0.3.0). Eight assets: four binaries, two feeds, `DisplayWeave-v0.3.0-source.tar.gz` and `SHA256SUMS.txt`. The source archive contains tracked source at the release tag, GPL-3.0, attribution and build scripts; its hash is in the checksum manifest. Binaries and source use GitHub Releases only. Live feeds use GitHub Pages. Previous assets remain immutable.

| Asset | SHA-256 |
| --- | --- |
| `DisplayWeave-macOS.zip` | `dacd185cbbce90361e5eb1e95ff7ebdd838f55c5d3ac704814d95e023e7ffaca` |
| `DisplayWeave-macOS.dmg` | `ef709366b3535188274b3ef74c3f39c104132d7b1a61f00ff8881401543163cb` |
| `DisplayWeave-Android.apk` | `5db3982be3c8ef6b6fe8d3279b570d2173569c5a2041b5223527ccb3c536c763` |
| `DisplayWeave-iOS-unsigned-resigning-input.ipa` | `9db070367ffe92ba4d77d5d8c574867dfce3e321e39b953ac5f3b5e9f1f86078` |
| `appcast.xml` | `9c620b488e08c0968ec19a60ff4829d98ec4aae082b56c1f764573eef1b98dc4` |
| `android-update.json` | `6315667d6aadabecf7c18f6ecc039b9f74b96f7105568152cc4e59f485e89669` |

Android signing certificate SHA-256: `89805f045800ea18b56b84b32e8e31b1710a3c7bf3c85fda54d260d1fc6d589d`.

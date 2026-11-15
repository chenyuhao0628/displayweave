[English](ROADMAP.md) | [简体中文](ROADMAP.zh-CN.md)

# DisplayWeave roadmap

Updated 2026-11-15. The current published stable release is **v0.3.5 (24)** (2026-11-10); post-`v0.3.5` capabilities listed under the source-branch section below are **not yet in published release downloads**. Mac desktop matching estimates size from available display data; see [release notes](docs/releases/v0.3.5.md), the [implementation/acceptance ledger](docs/verification/automatic-desktop-matching.md), and [protocol specification revision 3](docs/reference/protocol.md).

## Included in the current v0.3.5 stable release

- Android legacy V1 decoder recovery and asynchronous codec release, iOS Metal drawable/generation synchronization and rotated video admission, Mac receiver decoded-frame window gating, and bounded ADB/usbmux pipe and handshake handling.
- Opt-in Android experimental high-frame-rate trial and foreground keep-alive service, opt-in iPad native-resolution high-refresh trial, and rounded Mac app icon tiles.
- Generation-safe capture/encoder recovery, healthy-queue bitrate restoration, bounded Apple/Android decode pressure, aspect-correct Android video/input and resolution/frame-rate priority controls.
- Mac 4K encoding/cursor latency policies, bounded receiver pressure, 100 Mbps H.264 LAN presets and upstream capture/display recovery; see [the release notes](docs/archive/releases/release-notes-v0.3.0.md).
- Fixed Apple Development signing and upgrade comparisons; local permission continuity verified.
- Shared UI standards and main-screen OpenDisplay compatibility in both connection directions.
- Per-device automatic/receiver-matched/1080p/1440p/4K/iMac 4K/4.5K/5K desktop modes; bounded encoder work and default-on measured load adaptation preserve window layout.
- Default mutual TLS, invitation pairing, revocation and explicit legacy compatibility on Apple and Android.
- Apple HEVC/H.264 fallback and bounded 30–120fps negotiation.
- Consented Mac receiver keyboard/mouse input with release on focus, role and session changes.
- Opt-in Mac wired/Wi-Fi handover with bounded same-installation recovery.
- Advanced Pencil roll/eraser and consented, sender-defined shortcut actions.
- Mac process CPU metrics and Android bounded leased frame buffers.
- Public protocol specification and shared Swift/Java fixtures.
- GitHub-only distribution policy, Apple production archive/export preflight tooling and reproducible Android adaptive icons.

Each feature has its own guide, checks and compatibility boundaries in the ledger. Requested FPS is not measured rendered FPS.

## Implemented on the source branch (not yet in a published release)

- **Zero-ADB Android `AOA 2.0` wired USB & deterministic ADB arbitration:** User-space Android Open Accessory (`0x18D1:0x2D00`/`0x2D01`) transport with interface-gated `.adb`/`.mtp` USB probing, `16 KiB` bulk IN/OUT transfers with packet-aligned ZLP and `64`-empty-read bounds, default mutual TLS (`UsbmuxTLSRelay` ↔ `LoopbackAccessoryBridge` + `SecureSocketAdmission`), lock-inversion-free `UsbAccessoryReceiverTransport.Composite` USB↔Wi-Fi handover, deterministic ADB-first arbitration with actionable `0xE00002C5` exclusive-owner recovery hints, and non-persistent fallback suppression preventing AOA↔Wi-Fi oscillation.
- **Authenticated `udpMediaV1` low-latency transport, tight VBV pacing & settled crisp refresh:** RFC 5869 HKDF-SHA256 + AES-128-GCM session-scoped UDP media plane with a 16-byte AAD header, 1024-packet ROC anti-replay window, systematic GF(256) (`0x11d`) Cauchy/XOR FEC (`5%`–`20%` deducted before encoder bitrate), selective NACK retransmission, `1 ms` priority packet pacer, `NonBlockingUDPSocket` `EAGAIN` frame-completion accounting, receiver delay-gradient bandwidth estimation (`UDPDelayGradientBWE`), automatic `2.5 s` silence fallback to framed TCP, bounded jitter buffers (`3` frames / `45 ms` on Apple, `4` frames / `35 ms` on Android), `50 ms` (`1.5×` peak, `16,384 B` floor) VideoToolbox VBV `DataRateLimits`, `180 ms` post-motion settled crisp refresh (`MaxAllowedFrameQP = 20` safely restored to `51`), `250 ms` TCP ABR fast-drop hold, `65 ms` / `120 ms` TCP `ReceiverFrameAgePolicy`, `5 s` capture/decoder-FPS reconfiguration timeouts, and speed-priority encoding for `smooth` or `>= 90 fps`.
- **UDP cursor (`udpCursorV1`), unified UDP/TCP Opus system audio (`udpAudioV1` / `tcpAudioV1` / `audioOpusV1`), A/V lip-sync, hardware-gated 5K HEVC (`hevc5kV1`) and end-to-end Display P3 (`displayP3`):** `125 Hz` authenticated UDP normalized cursor coordinates (17-byte payload; cursor PNG bitmaps stay on TCP), opt-in `48 kHz` stereo system audio (`20 ms` / `960`-frame `128 kbps` Opus with `formatFlags = 1` over Apple `AudioConverter` and Android `MediaCodec`, automatic `5 ms` / `960 B` S16LE fallback, `<= 4,096 B` `"audioFrame"` TCP controls across USB/DirectCable/TCP-fallback with `pendingSends > 2` drop, `120 ms` / `5,760`-frame ring ceiling, and `15…90 ms` clock-offset-invariant A/V lip-sync watermark + drift trim), Mac hardware-HEVC `5120 × 2880 @ 60` (`2880 × 5120 @ 60` portrait) negotiation with H.264 strictly capped at `4096 × 2304`, and `CGVirtualDisplay` CIE 1931 Display P3 primaries + Apple/Android wide-gamut `displayP3` negotiation.
- **Physical `panel` millimeter telemetry, full iPadOS multitasking windowing & cross-platform stylus/desktop input:** Mac, iOS/iPadOS and Android `millimetersWide`/`millimetersHigh` reporting with macOS 26.1+ `208 × 96 mm` (`>= 20,000 mm²` area floor, `<= 2,000 mm` edge cap) virtual-display sizing, `UIRequiresFullScreen` removal + `320 × 320` iPad scene sizing + deduplicated `150 ms`-debounced live Split View / Slide Over / Stage Manager window geometry updates + swapped `(w, h) == (cfgH, cfgW)` rotation acceptance, consented `mac-input-v1` external hardware keyboard/mouse/trackpad forwarding on iPadOS/iOS and Android, and Android active stylus `pencil-v1` / `pencil-v2` / `pencilAction` support.
- **Direct-socket, LAN diagnostics, notarized DMG & release-feed hardening:** `NWParameters.preferNoProxies = true` on Mac sender LAN/Bonjour TCP connections (explicitly excluding loopback `127.0.0.1` / `::1` / `localhost` ADB, AOA and usbmux tunnels via `LANProxyBypassPolicy`), Local Network, AWDL contention, and conservative `8 s` empty-Wi-Fi AP-isolation diagnostics, Unicode-scalar UTF-8 invitation truncation, Android `dependenciesInfo` removal, notarized/stapled `DisplayWeave-macOS.dmg` alongside `DisplayWeave-macOS.zip` in `tools/apple-distribution.py`, GitHub Pages live release-feed overlay protection (`appcast.xml`, `android-update.json` verified against `SHA256SUMS.txt`), and 20 Revision 2/3 Swift/Java `udpMediaV1` / `tcpAudioV1` / `audioOpusV1` golden vectors; see [architecture](ARCHITECTURE.md) and [protocol contract](docs/reference/protocol.md).

## Earlier implementation baseline

The local p8 artifact included the p7 Mac send/receive LAN mirror/extend preview, four-surface UI refactor, selected upstream startup recovery, bounded queues/framing, Mac hardware-gated HEVC, interface-pinned direct-link candidates and basic Pencil. Earlier previews exercised Android dynamic ADB-forward USB, bounded USB/Wi-Fi recovery and one current iPhone/Android concurrent session. See the dated release notes and physical reports; historical evidence is not automatically evidence for new secure transport.

## External prerequisites

Production Apple distribution requires the maintainer's Developer ID Application / Apple Distribution identities, provisioning and notarization access. Tooling is implemented, but actual production signing/export/notarization is blocked. Approved editable/transparent/dark/monochrome brand masters and licensed promotional screenshots are also missing; current raster derivatives remain in use.

## Physical acceptance

Two-Mac automatic matching and native 5K clarity, both-direction mirror/extend, Wi-Fi/Ethernet/Thunderbolt Bridge route changes, sleep/wake, hotplug, Intel runtime, input/layout/shortcut behavior; real Pencil and Android active-stylus gestures/rotation/eraser and drawing applications; iPadOS Stage Manager / Split View / Slide Over live resizing and iPadOS/Android external keyboard/trackpad/mouse `mac-input-v1` ergonomics; Apple/Android HEVC/Display P3/high-refresh display behavior; Android zero-ADB `AOA 2.0` hotplug, permission prompt, and ADB arbitration; `udpMediaV1` / `udpCursorV1` / `udpAudioV1` / `tcpAudioV1` / `audioOpusV1` LAN/USB jitter, loss recovery, A/V lip-sync, and paired LAN/USB performance and reconnects. Published `v0.3.5` downloads remain capped at the `4096 × 2304` Apple video envelope and ADB-only Android USB; source-branch hardware-gated `5120 × 2880 @ 60` HEVC (`hevc5kV1`) and `AOA 2.0` USB await physical device acceptance.

Also pending: two simultaneous Android receivers, controlled same-resolution/codec/bitrate USB-versus-Wi-Fi and UDP-versus-TCP benchmarks, 30-minute/2-hour endurance, and broader OS/SoC/cable matrices. Test virtual displays only with an independent online display. See [acceptance](docs/archive/plans/roadmap-and-acceptance.md).

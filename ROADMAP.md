[English](ROADMAP.md) | [简体中文](ROADMAP.zh-CN.md)

# DisplayWeave roadmap

Updated 2026-10-23. The [feature ledger](docs/feature-completion.md) records each implementation. The current release is v0.3.0 (19), adding Mac 4K latency improvements, a 100 Mbps H.264 LAN ceiling and reviewed upstream recovery fixes. See [release notes](docs/release-notes-v0.3.0.md) for artifacts and verification boundaries.

## Included in the current v0.3.0 stable release

- Mac 4K encoding/cursor latency policies, bounded receiver pressure, 100 Mbps H.264 LAN presets and upstream capture/display recovery; see [the release notes](docs/release-notes-v0.3.0.md).
- Fixed Apple Development signing and upgrade comparisons; local permission continuity verified.
- Shared UI standards and main-screen OpenDisplay compatibility in both connection directions.
- Per-device Native/1080p/1440p/4K extension resolution.
- Default mutual TLS, invitation pairing, revocation and explicit legacy compatibility on Apple and Android.
- Apple HEVC/H.264 fallback and bounded 30–120fps negotiation.
- Consented Mac receiver keyboard/mouse input with release on focus, role and session changes.
- Opt-in Mac wired/Wi-Fi handover with bounded same-installation recovery.
- Advanced Pencil roll/eraser and consented, sender-defined shortcut actions.
- Mac process CPU metrics and Android bounded leased frame buffers.
- Public protocol specification and shared Swift/Java fixtures.
- GitHub-only distribution policy, Apple production archive/export preflight tooling and reproducible Android adaptive icons.

Each feature has its own guide, checks and compatibility boundaries in the ledger. Requested FPS is not measured rendered FPS.

## Earlier implementation baseline

The local p8 artifact included the p7 Mac send/receive LAN mirror/extend preview, four-surface UI refactor, selected upstream startup recovery, bounded queues/framing, Mac hardware-gated HEVC, interface-pinned direct-link candidates and basic Pencil. Earlier previews exercised Android dynamic ADB-forward USB, bounded USB/Wi-Fi recovery and one current iPhone/Android concurrent session. See the dated release notes and physical reports; historical evidence is not automatically evidence for new secure transport.

## External prerequisites

Production Apple distribution requires the maintainer's Developer ID Application / Apple Distribution identities, provisioning and notarization access. Tooling is implemented, but actual production signing/export/notarization is blocked. Approved editable/transparent/dark/monochrome brand masters and licensed promotional screenshots are also missing; current raster derivatives remain in use.

## Physical acceptance

Two-Mac both-direction mirror/extend, Wi-Fi/Ethernet/Thunderbolt Bridge route changes, sleep/wake, hotplug, Intel runtime, input/layout/shortcut behavior; real Pencil gestures/rotation/eraser and drawing applications; Apple HEVC/high-refresh display behavior; paired LAN/USB performance and reconnects.

Also pending: two simultaneous Android receivers, controlled same-resolution/codec/bitrate USB-versus-Wi-Fi benchmarks, 30-minute/2-hour endurance, and broader OS/SoC/cable matrices. Test virtual displays only with an independent online display. See [acceptance](docs/roadmap-and-acceptance.md).

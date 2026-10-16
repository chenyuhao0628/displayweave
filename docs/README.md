[English](README.md) | [简体中文](README.zh-CN.md)

# DisplayWeave Documentation

## Current user guides

- [Public protocol contract and shared fixtures](protocol.md)
- [Advanced Pencil input (source)](pencil-advanced.md)
- [Mac receiver keyboard and mouse (source)](mac-receiver-input.md)
- [Secure connections and pairing (source)](secure-transport.md) and [design / remaining integration](secure-transport-design.md)
- [Mac wired / Wi-Fi handover (source)](mac-lan-handover.md)
- [Apple receiver HEVC and high refresh (source)](apple-video.md)
- [Per-device desktop resolution (source)](desktop-resolution.md)
- [Active feature completion plan and evidence](feature-completion.md)
- [HEVC, direct-link and Pencil usage / current evidence](hevc-wired-pencil.md)
- [HEVC, wired discovery and Pencil design / acceptance](hevc-wired-pencil-plan.md)
- [2026-10-16 source upgrade audit and hardware limits](source-upgrade-audit-2026-10-16.md) and [upstream integration decisions](upstream-integration-2026-10-16.md)
- [UI standard](ui-guidelines.md) and [source upgrade plan](upgrade-plan.md)
- [Development workflow and current Codex guidance](development.md)
- [Mac-to-Mac LAN (experimental preview)](mac-to-mac.md) and [design/upstream assessment](mac-to-mac-design.md)

- [Development preview distribution](development-preview.md)
- [`v0.2.0-preview.2` release notes](release-notes-v0.2.0-preview.2.md)
- [`v0.2.0-preview.3` release notes](release-notes-v0.2.0-preview.3.md)
- [`v0.2.0-preview.4` release notes](release-notes-v0.2.0-preview.4.md)
- [`v0.2.0-preview.5` release notes](release-notes-v0.2.0-preview.5.md)
- [`v0.2.1` release notes](release-notes-v0.2.1.md)
- [`v0.2.1-p1` release notes](release-notes-v0.2.1-p1.md)
- [`v0.2.1-p2` release notes](release-notes-v0.2.1-p2.md)
- [`v0.2.1-p3` release notes](release-notes-v0.2.1-p3.md)
- [`v0.2.1-p4` release notes](release-notes-v0.2.1-p4.md)
- [`v0.2.1-p5` release notes](release-notes-v0.2.1-p5.md)
- [`v0.2.1-p6` release notes](release-notes-v0.2.1-p6.md)
- [`v0.2.1-p7` release notes](release-notes-v0.2.1-p7.md)
- [`v0.2.1-p8` release notes](release-notes-v0.2.1-p8.md) and [local build publication](local-release.md)
- [Release checklist](release-checklist.md)
- [Mac and Android automatic updates](automatic-updates.md)
- [Stability and physical-device evidence](stability-test-report.md)
- [Performance metrics audit](performance-metrics-audit.md)
- [Android stability and latency audit](android-stability-latency-audit.md), [connection generation model](android-connection-generation.md), [Protocol V2 negotiation](android-protocol-v2-negotiation.md), [binary frame header/allocation path](android-binary-frame-header-v2.md), [thermal/power metrics](android-thermal-power-metrics.md), [frame-size negotiation](frame-size-negotiation.md), [decoder low-latency selection](android-decoder-low-latency.md), [decoder throughput recovery](android-decoder-throughput-recovery.md), [WiFi low latency / Surface frame rate](android-wifi-low-latency-surface-frame-rate.md), and [drop-reason policy](android-drop-reason-policy.md)
- [Short benchmark guide](benchmark-guide.md)
- [Latency measurement](latency-measurement.md)
- [USB versus WiFi benchmark protocol](usb-vs-wifi-benchmark.md)
- [Bitrate modes](bitrate-modes.md), [adaptive bitrate](adaptive-bitrate.md), [local fast congestion decrease](mac-local-fast-congestion-decrease.md), [queue analysis](low-latency-queue-analysis.md), and [keyframe strategy](keyframe-strategy.md)
- [Short USB/WiFi evidence](usb-vs-wifi-short-benchmark.md), [Android quick recovery V2 evidence](android-quick-recovery-v2.md), and [multi-device architecture audit](multi-device-architecture-audit.md)
- [Roadmap and acceptance](roadmap-and-acceptance.md)
- [Android high-refresh migration evidence](120hz-migration-plan.md)
- [Brand assets](brand-assets.md) and [brand/documentation audit](branding-and-doc-audit.md)

Root guides cover [architecture](../ARCHITECTURE.md), [security](../SECURITY.md), [contributing](../CONTRIBUTING.md), and the [Android receiver](../AndroidReceiver/README.md).

## Historical/internal records

The [`v0.2.0-preview.1` release notes](release-notes-v0.2.0-preview.1.md),
[Preview 0.1 / Preview 2 release notes](release-notes-preview-0.1.md),
files under `docs/superpowers/specs/` and `docs/superpowers/plans/`, and
`android-usb-transport-design.md` record prior releases or design decisions.
They may remain in their authored language and must not be treated as the only
current user instructions.

## Status vocabulary

- **Verified:** exercised on the hardware named in the relevant report.
- **Experimental:** implemented, but performance or compatibility remains hardware-dependent.
- **Deferred:** not completed and not claimed.

Preview 2 still defers two simultaneous Android devices, the controlled same-condition USB/WiFi benchmark, and 30-minute/2-hour endurance runs.

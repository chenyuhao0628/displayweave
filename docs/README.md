[English](README.md) | [简体中文](README.zh-CN.md)

# DisplayWeave Documentation

## Current user guides

- [Development preview distribution](development-preview.md)
- [Preview 0.1 / Preview 2 release notes](release-notes-preview-0.1.md)
- [Release checklist](release-checklist.md)
- [Stability and physical-device evidence](stability-test-report.md)
- [Performance metrics audit](performance-metrics-audit.md)
- [Short benchmark guide](benchmark-guide.md)
- [Latency measurement](latency-measurement.md)
- [USB versus WiFi benchmark protocol](usb-vs-wifi-benchmark.md)
- [Bitrate modes](bitrate-modes.md), [adaptive bitrate](adaptive-bitrate.md), [queue analysis](low-latency-queue-analysis.md), and [keyframe strategy](keyframe-strategy.md)
- [Short USB/WiFi evidence](usb-vs-wifi-short-benchmark.md), [quick recovery checklist](quick-recovery-checklist.md), and [multi-device architecture audit](multi-device-architecture-audit.md)
- [Roadmap and acceptance](roadmap-and-acceptance.md)
- [Android high-refresh migration evidence](120hz-migration-plan.md)
- [Brand assets](brand-assets.md) and [brand/documentation audit](branding-and-doc-audit.md)

Root guides cover [architecture](../ARCHITECTURE.md), [security](../SECURITY.md), [contributing](../CONTRIBUTING.md), and the [Android receiver](../AndroidReceiver/README.md).

## Historical/internal records

Files under `docs/superpowers/specs/` and `docs/superpowers/plans/`, plus `android-usb-transport-design.md`, record design and implementation decisions. They may remain in their authored language and must not be treated as the only current user instructions.

## Status vocabulary

- **Verified:** exercised on the hardware named in the relevant report.
- **Experimental:** implemented, but performance or compatibility remains hardware-dependent.
- **Deferred:** not completed and not claimed.

Preview 2 still defers two simultaneous Android devices, the controlled same-condition USB/WiFi benchmark, and 30-minute/2-hour endurance runs.

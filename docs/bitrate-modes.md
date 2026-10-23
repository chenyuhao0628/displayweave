[English](bitrate-modes.md) | [简体中文](bitrate-modes.zh-CN.md)

# Bitrate modes

Auto is the default and adapts within codec/transport bounds. Manual selects a fixed preset and clamps it to the active path. Benchmark exposes 10–200 Mbps for local experiments only and displays these warnings: Experimental; May increase latency; May cause queueing; For local benchmark only.

**v0.3.0 bounds (2026-10-23):** HEVC LAN 12–100, HEVC USB 20–160, H.264 LAN 8–100, and H.264 USB 10–100 Mbps. LAN includes Ethernet and Wi-Fi; its internal policy name remains `wifi`. The H.264 LAN ceiling was 60 Mbps in preview.3; v0.3.0 permits Manual 80/100 Mbps without Benchmark mode. See [release notes](release-notes-v0.3.0.md). Auto also uses a transport-aware initial estimate; for example, 3040×1904 at 120 fps with High-quality HEVC starts around 112 Mbps on USB. The settings UI filters manual presets using the selected codec and transport; the sender revalidates the value using the negotiated codec and actual transport.

Target Bitrate is encoder intent. Actual Bitrate is measured socket throughput. They are displayed and recorded separately.

Raising the ceiling does not force 100 Mbps. High-quality H.264 at 3840×2160/60 still starts near 49.77 Mbps in Auto. To request 100 Mbps, select H.264 and Manual → 100 Mbps. Mac local recovery restores the initial Auto target after active, uncongested windows; it does not ramp an otherwise healthy 50 Mbps stream to 100 Mbps. See [the source audit and local evidence](mac-4k-latency.md).

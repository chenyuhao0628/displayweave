[English](desktop-resolution.md) | [简体中文](desktop-resolution.zh-CN.md)

# Per-device desktop resolution

Included in v0.3.0-preview.1. In **Send → Extend**, connect a receiver and use **Desktop pixels** in its connection row: Native, 1920×1080, 2560×1440 or 3840×2160. Portrait receivers swap width/height automatically. The selection is retained by receiver installation identity across LAN/USB and restarts. Old receivers without an identity use Native. Resetting/reinstalling a receiver may create a new identity.

Changing the selection stops and rebuilds only that device's session after capture and transport cleanup. Other active devices keep streaming. The picker is disabled during replacement. Mirror captures the physical source display and does not offer a virtual-desktop selector.

The values are **framebuffer pixels**, not logical points. A Retina virtual display uses 2× backing: 3840×2160 pixels gives 1920×1080 logical points; 1920×1080 pixels gives 960×540 points. A non-Retina Mac uses 1×. Native preserves receiver-derived points and scale. Fixed modes are 16:9 (9:16 portrait); receivers with a different aspect ratio show letterboxing.

Quality still independently scales capture/encoding to 50%, 75% or 100%. Mac decoding limits can further reduce encoded size/FPS; mobile peers without explicit decoder dimensions stay within their advertised panel raster. This does not shrink the selected desktop layout. The connection status reports encoded dimensions, so those can differ from the chosen desktop pixels. Lower quality saves bandwidth, whereas changing desktop pixels rearranges the desktop.

Automated evidence: geometry/orientation and invalid bounds, independent settings round trips, bounded 128-device preference storage, encoder limits, and mirror aspect ratio. Existing session-lifetime tests cover cleanup before replacement. Mac universal Debug build and 38 Swift suites passed. Physical acceptance remains: two simultaneous receivers, change only one mode, verify windows and cursor mapping, portrait rotation, disconnect/reconnect, and display removal with an independent display online.

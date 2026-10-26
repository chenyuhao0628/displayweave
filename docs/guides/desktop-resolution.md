[English](desktop-resolution.md) | [简体中文](desktop-resolution.zh-CN.md)

# Per-device desktop resolution

Included in v0.3.1. In **Send → Extend**, connect a receiver and use **Desktop pixels** in its connection row: Native, 1920×1080, 2560×1440 or 3840×2160. Portrait receivers swap width/height automatically. The selection is retained by receiver installation identity across LAN/USB and restarts. Old receivers without an identity use Native. Resetting/reinstalling a receiver may create a new identity.

Changing the selection stops and rebuilds only that device's session after capture and transport cleanup. Other active devices keep streaming. The picker is disabled during replacement. Mirror captures the physical source display and does not offer a virtual-desktop selector.

The values are **framebuffer pixels**, not logical points. A Retina virtual display uses 2× backing: 3840×2160 pixels gives 1920×1080 logical points; 1920×1080 pixels gives 960×540 points. A non-Retina Mac uses 1×. Native preserves receiver-derived points and scale. Fixed modes are 16:9 (9:16 portrait); receivers with a different aspect ratio show letterboxing.

Quality still independently scales capture/encoding to 50%, 75% or 100%. Mac decoding limits can further reduce encoded size/FPS; mobile peers without explicit decoder dimensions stay within their advertised panel raster. This does not shrink the selected desktop layout. The connection status reports encoded dimensions, so those can differ from the chosen desktop pixels. Lower quality saves bandwidth, whereas changing desktop pixels rearranges the desktop.

## iMac improvements in source after v0.3.1

The updated **Desktop size** picker adds iMac 4K (4096×2304), 4.5K (4480×2520) and 5K (5120×2880). At 2× these provide 2048×1152, 2240×1260 and 2560×1440 logical points. Existing saved modes keep their meanings. **Match receiving screen** replaces the generic Native label and shows announced logical dimensions, including the receiver's current macOS scaling. The card shows logical desktop size/backing pixels separately from the negotiated video raster.

For two 5K iMacs with matching macOS scaling, start with **Match receiving screen** and fullscreen reception. Selecting ordinary 3840×2160 instead gives only 1920×1080 points and enlarges windows when stretched across the 5K screen. A receiving window smaller than the screen always scales the whole remote desktop to fit. These desktop presets do not lift the 4096×2304 Apple video decoding envelope.

**Adapt Mac encoder load** is enabled by default in the source settings. Resolution priority preserves encoded detail and lowers FPS under sustained measured encoder pressure; frame-rate priority lowers video raster first. Both preserve desktop geometry. Healthy active windows can restore the original operating point. It can be disabled and is off in bitrate benchmark mode. For responsive interaction, select frame-rate priority; reducing desktop size is unnecessary. See [evidence and acceptance](../verification/imac-resolution-performance.md). These changes are not yet in a published download.

Automated evidence: geometry/orientation and invalid bounds, independent settings round trips, bounded 128-device preference storage, encoder limits, and mirror aspect ratio. Existing session-lifetime tests cover cleanup before replacement. Mac universal Debug build and 38 Swift suites passed. Physical acceptance remains: two simultaneous receivers, change only one mode, verify windows and cursor mapping, portrait rotation, disconnect/reconnect, and display removal with an independent display online.

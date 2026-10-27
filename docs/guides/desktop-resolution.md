[English](desktop-resolution.md) | [简体中文](desktop-resolution.zh-CN.md)

# Per-device desktop resolution

## Automatic matching in the unreleased source

The source now offers **Automatic matching** in each Extend session. New installations use it by default. An existing installation keeps its saved per-device presets and its previous default, because older versions did not distinguish an explicit **Match receiving screen** choice from an absent preference. Choose **Automatic matching** once for an existing device to change that device; changing it reconnects only that session. A peer without a usable installation identity continues to use receiver-matched geometry.

For a Mac receiver, the sender uses the eligible display adjacent to the saved virtual-display position, or the sender's main display when no adjacent display is known. DisplayWeave's own virtual displays and mirror followers are excluded. The receiver's current aspect ratio and reported usable screen geometry determine the virtual desktop shape. If both sides report plausible physical dimensions, those values inform an estimate of point density; dimensions resembling a 72-dpi fallback, inconsistent aspect ratios, and missing or invalid values are ignored. Without both sizes, the estimate matches the reference display's long logical edge instead. For iOS/Android receivers, automatic mode currently retains their receiver-derived geometry.

These are estimates, not calibrated physical measurements: display-reported millimeters can still be inaccurate, different panel sizes affect perceived size, and a windowed receiver or black bars change the visible content area. Fullscreen on the intended receiving display is the appropriate starting point. The row displays the resolved desktop and the actual negotiated video size separately. A 1× Mac receiver may use a 2× virtual backing when that supplies additional detail. The video remains limited by quality, decoder capability and encoder-load adaptation.

The sender watches screen changes with a 2.5-second debounce and a 10-second minimum interval between automatic rebuild requests. It only rebuilds the affected session when the computed desktop actually changes, and checks again after a rebuild in case a screen changed while it was busy. When no eligible reference display is available it leaves the active desktop alone; the next valid screen change or reconnect re-evaluates it. Receiver screen/orientation announcements retain the existing reconfiguration path. Automatic matching does **not** expand the existing 4096×2304 Apple video envelope or guarantee native 5K video. A 5K-sized desktop can therefore still appear soft; the row warns when video dimensions are below desktop backing pixels. This source feature is not included in the published v0.3.2 download.

See the [verification record](../verification/automatic-desktop-matching.md) for automated coverage and the remaining two-device acceptance work.

## Published v0.3.2

In v0.3.2, connect a receiver in **Send → Extend** and use **Desktop size** in its connection row: Match receiving screen, 1920×1080, 2560×1440, 3840×2160, or iMac 4K/4.5K/5K. Portrait receivers swap width/height automatically. The selection is retained by receiver installation identity across LAN/USB and restarts. Old receivers without an identity use Native. Resetting/reinstalling a receiver may create a new identity.

Changing the selection stops and rebuilds only that device's session after capture and transport cleanup. Other active devices keep streaming. The picker is disabled during replacement. Mirror captures the physical source display and does not offer a virtual-desktop selector.

The values are **framebuffer pixels**, not logical points. A Retina virtual display uses 2× backing: 3840×2160 pixels gives 1920×1080 logical points; 1920×1080 pixels gives 960×540 points. A non-Retina Mac uses 1×. Native preserves receiver-derived points and scale. Fixed modes are 16:9 (9:16 portrait); receivers with a different aspect ratio show letterboxing.

Quality still independently scales capture/encoding to 50%, 75% or 100%. Mac decoding limits can further reduce encoded size/FPS; mobile peers without explicit decoder dimensions stay within their advertised panel raster. This does not shrink the selected desktop layout. The connection status reports encoded dimensions, so those can differ from the chosen desktop pixels. Lower quality saves bandwidth, whereas changing desktop pixels rearranges the desktop.

## iMac improvements in v0.3.2

The updated **Desktop size** picker adds iMac 4K (4096×2304), 4.5K (4480×2520) and 5K (5120×2880). At 2× these provide 2048×1152, 2240×1260 and 2560×1440 logical points. Existing saved modes keep their meanings. **Match receiving screen** replaces the generic Native label and shows announced logical dimensions, including the receiver's current macOS scaling. The card shows logical desktop size/backing pixels separately from the negotiated video raster.

For two 5K iMacs with matching macOS scaling, start with **Match receiving screen** and fullscreen reception. Selecting ordinary 3840×2160 instead gives only 1920×1080 points and enlarges windows when stretched across the 5K screen. A receiving window smaller than the screen always scales the whole remote desktop to fit. These desktop presets do not lift the 4096×2304 Apple video decoding envelope.

**Adapt Mac encoder load** is enabled by default in settings. Resolution priority preserves encoded detail and lowers FPS under sustained measured encoder pressure; frame-rate priority lowers video raster first. Both preserve desktop geometry. Healthy active windows can restore the original operating point. It can be disabled and is off in bitrate benchmark mode. For responsive interaction, select frame-rate priority; reducing desktop size is unnecessary. See [evidence and acceptance](../verification/imac-resolution-performance.md).

Automated evidence: geometry/orientation and invalid bounds, independent settings round trips, bounded 128-device preference storage, encoder limits, and mirror aspect ratio. Existing session-lifetime tests cover cleanup before replacement. Mac universal Debug build, 63 Swift suites and the capture/load/admission fixtures passed. Physical acceptance remains: two simultaneous receivers, change only one mode, verify windows and cursor mapping, portrait rotation, disconnect/reconnect, and display removal with an independent display online.

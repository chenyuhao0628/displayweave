[English](automatic-desktop-matching.md) | [简体中文](automatic-desktop-matching.zh-CN.md)

# Automatic desktop matching

Date: 2026-10-27. This describes unreleased source changes, not the published v0.3.2 download. See the [desktop resolution guide](../guides/desktop-resolution.md) for operation and limitations.

## Implementation

Automatic matching estimates a Mac receiver's logical desktop from an eligible sender reference display, receiver aspect ratio, and plausible reported physical dimensions when available. Missing or implausible dimensions fall back to proportional matching. Mobile receivers and peers without an installation identity retain receiver-derived geometry. A 1× Mac receiver can select 2× virtual backing where necessary for detail. Video negotiation and fallback remain bounded by the existing codec envelopes.

[Apple documents](https://developer.apple.com/documentation/coregraphics/cgdisplayscreensize(_:)) that `CGDisplayScreenSize` can estimate dimensions at 72 dpi when display EDID is unavailable. The matching policy rejects values close to that fallback, but a plausible report is still not a physical measurement.

Old preference maps and the old implicit receiver-matched default are preserved when recognizable legacy settings exist. New installations default to automatic matching, and the chosen default is recorded before later connection settings can change that classification. A completely preference-free older installation cannot be distinguished from a new one. An automatic sender observes screen changes with debounce and cooldown, reconfigures only a changed desktop, and retains the active desktop while no reference is available. Each callback is checked against the live session, display and receiver configuration.

## Automated verification

`DesktopResolutionSelfTest` covers the reported 2048×1152-point case, portrait and 1×/2× choices, physical-size validation and missing/malformed fields, bounded geometry, receiver video limits, per-device settings and legacy migration. `DesktopMatchMonitorSelfTest` covers coalescing, cooldown, reconsideration after a busy rebuild and teardown; `DesktopMatchDisplaysSelfTest` queries the current display read-only or reports SKIP. `MacReceiverNetworkSelfTest` exercises the optional physical dimensions in a loopback hello. `tools/test-desktop-match-update.py` executes the current production update and reconfiguration-scheduling methods with stubbed display operations, including missing reference, unchanged geometry, independent sessions, stopped state, replaced display, stale receiver information and the post-rebuild recheck.

The local Swift standalone gate, universal unsigned Mac Debug build, documentation checks and whitespace check are the reproducible source checks. The normal signed development Run action was also used; it does not replace the installed release.

## Local observations

On an Apple M5 Mac running macOS 26.5.2 with its built-in display online, the read-only reference-display query succeeded. The isolated AppKit receiver fixture opened and closed its synthetic video window, entered/exited fullscreen and handled simulated sleep/wake. Three cycles each of 800×600-point 1× and 2× virtual displays passed creation, mode and removal checks.

A separate virtual-display check used the customer-style synthetic 2048×1152-point reference and a 2560×1440-point 2× receiver. The policy selected 2048×1152 at 2×, and the local system selected a 4096×2304 backing mode; the temporary display was removed. No desktop capture or two-device video was involved in that check.

The signed development app's sender home screen was visually inspected with no receiver connected. A separate isolated preview rendered the production `SessionRow` with simulated connected-session data, a 5K desktop, the video-size warning and a long device name at a 480×440-point window in light and dark appearances; no text overlap was observed. This preview did not exercise a real connected session, live updates or keyboard navigation.

## Deferred physical acceptance

- On the customer's sender, ordinary display and Mac receiver, record model, OS, app versions, physical screen sizes, current logical modes, receiver fullscreen/content area, desktop backing, encoded raster, codec, target and rendered FPS. Compare the same window across screens at 2048×1152 and 2560×1440 sender settings.
- Exercise different-sized and portrait displays, a 1× receiver, windowed reception and black bars; compare window/cursor size with actual measurements. Test reconnect, receiver rotation, sender mode changes, hotplug, temporary reference loss and two simultaneous receivers without stale callbacks or repeated rebuilds.
- Native 5K video remains deferred. The current Apple envelope is 4096×2304; a 5120×2880 desktop can still transmit at 4096×2304 and look soft. A future expansion requires per-codec encoder/decoder capability evidence, bounded fallback and real Intel/Apple hardware performance tests. The local mode test does not establish 5K sharpness, throughput or endurance.

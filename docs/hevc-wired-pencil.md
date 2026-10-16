[English](hevc-wired-pencil.md) | [简体中文](hevc-wired-pencil.zh-CN.md)

# HEVC, direct-link Macs and Apple Pencil

For current v0.3.0-preview.1 behavior, see [resolution](desktop-resolution.md), [Apple video](apple-video.md), [secure pairing](secure-transport.md), [wired/Wi-Fi handover](mac-lan-handover.md) and [advanced Pencil](pencil-advanced.md). These extensions are included; physical acceptance remains pending. The following p7/p8 baseline and dated evidence are historical, not current feature limits.

## Historical p7/p8 baseline

Packaged in the v0.2.1-p7 development preview on 2026-10-16. Hardware-dependent behavior remains experimental. See the [design and upstream provenance](hevc-wired-pencil-plan.md).

## Resolution switching

Settings → Stream → Quality rebuilds connections with 50% (Low), 75% (Balanced / Smooth), or 100% (High) capture scaling. Codec and receiver limits can reduce the final raster further. The extended desktop retains receiver-derived logical dimensions; there is no separate per-device 1080p/1440p/4K desktop-mode picker. Changing quality can interrupt an active session and does not promise a particular encoded resolution.

## Mac HEVC

Install v0.2.1-p7 or a newer compatible build on both Macs. Set Codec to Auto or HEVC. HEVC is selected when the sender has a hardware encoder and the receiver explicitly offers hardware decoding. H.264 remains available for old receivers, unsupported hardware and explicit H.264 preference. iOS video remains H.264; Android retains its own codec/refresh negotiation.

The receiver status names the actual codec. Both codecs stay within 4096×2304 landscape or 2304×4096 portrait and at most 60 fps. The sender also respects receiver pixel throughput and the H.264 fallback envelope. HEVC does not enable unrestricted 5K/120 fps.

Encoder creation/runtime failure falls back to H.264. A receiver HEVC parse/decoder failure requests fallback once, clears video state, and waits up to three seconds for H.264 configuration. Repeated HEVC configurations after failure are rejected. If fallback fails, choose H.264 and reconnect. Real decoding performance depends on the two machines and network.

After a failure, the sender keeps H.264 for that Mac connection, including display-size changes and repeated capability announcements. A new connection may negotiate HEVC again.

## Connect Macs by cable

1. Establish a working Thunderbolt Bridge or direct Ethernet network between the Macs. An ordinary USB-C charging/data cable does not by itself provide Mac-to-Mac networking.
2. Select Receive on one Mac. On the sender choose Auto or LAN, then look for **直连候选 · interface** in its device row.
3. Connect. Bonjour resolution and TCP are pinned to that interface; the active session shows **有线 · interface**. If Wi-Fi is also enabled, the pinned connection does not silently use it.
4. To connect on appearance, enable **自动连接直连 Mac** in Settings → General. This is off by default, requires Auto/LAN mode and respects `-autostart NO`. There is one auto attempt per appearance; manual disconnect suppresses subsequent cable auto-connect until a manual connection or app restart. It does not replace an existing Wi-Fi session automatically.
5. If an existing Wi-Fi session should move to the cable, disconnect it and reconnect after the candidate appears. If the cable fails, disconnect and use normal LAN after removing the cable, or retry the cable after fixing it.

Classification requires a Mac TXT record and a wired, non-internal interface with a nonempty set of exclusively link-local addresses. A DHCP-less Ethernet switch can satisfy the same heuristic: **candidate does not prove a dedicated physical cable or authenticate a peer**. Static-IP or routed Ethernet remains available through ordinary LAN discovery. The inherited transport still requires a trusted network. No remote shutdown command was added.

Switching transport mode ends sessions excluded by the new mode before rebuilding permitted sessions. USB-only excludes Mac direct-link networking as well as Wi-Fi; LAN-only cancels pending Android USB recovery. When no session is active, changing mode immediately reevaluates the existing auto-connect rules.

## Apple Pencil on iPad

Install the matching v0.2.1-p7 or newer iOS/iPadOS and Mac builds; the public IPA requires re-signing. Connect as usual over USB or LAN, then grant the Mac Accessibility permission for input. The iOS settings show **压感与倾角** after capability confirmation, or **兼容触控** for an older sender. This status describes the negotiated protocol, not proof that an attached Pencil or drawing app supports every feature.

Pencil contact forwards pressure and tilt as native tablet events. Supported iPads/Pencils also send hover. Finger scrolling is separated from pen contact; direct touches are suppressed while the Pencil is drawing or hovering. At most 32 real coalesced samples are forwarded per event; predicted Pencil points are not committed as ink. Existing finger input remains available after the pen leaves.

Tilt preserves the view's screen axes: right/left maps to tablet X, down/up to tablet Y, and an upright Pencil has zero tilt. Automated tests cover all four directions and the resulting CoreGraphics fields.

Old Mac senders receive normal touch down/move/up without pressure. A capability reply arriving mid-stroke applies to the next stroke, so the current press is released using the protocol that started it. Cancellation, view removal, connection replacement, backgrounding and sender teardown release pen/finger state. Control congestion closes the affected session instead of retaining an unbounded input backlog.

Barrel roll, squeeze, Pencil double-tap mapping, eraser tooling and application-specific brush integration are not implemented. Physical pressure, tilt, hover and palm rejection must be tested with the intended iPad/Pencil/drawing application.

## Verification record

| Check | Result on 2026-10-16 |
| --- | --- |
| Swift standalone regression | PASS, 37 suites |
| Mac build | PASS, unsigned Debug arm64 + x86_64 |
| iOS build | PASS, unsigned iOS Simulator Debug |
| Real VideoToolbox samples | H.264 and HEVC encoded samples parsed; loopback configuration switching, malformed HEVC fallback and timeout passed |
| Native tablet event tests | PASS using an in-memory event sink; pressure, tilt, coordinates, palm isolation and idempotent cancel; no events posted to the desktop |
| Direct-link policy tests | PASS for strict address/interface classification, opt-in, manual opt-out and one attempt per appearance |
| Input control budget tests | PASS for pre-dispatch admission, overflow latch, concurrent calls and stale completion isolation |
| Android | Gradle test + assembleDebug PASS |
| Website / release consistency | Production bilingual build and existing v0.2.1-p6 asset/feed checks PASS |
| Documentation | 64 bilingual pairs checked |
| UIKit gesture runtime / new UI rendering | Not exercised this round; no running simulator available |
| Virtual-display / physical Mac tests | SKIP: host lid closed, no independent external display verified; no WindowServer or remote-access changes |
| Two-Mac cable / actual Pencil | Not available; pending physical acceptance |

Compilation for Intel is not Intel runtime validation. Parsing real encoded samples is not a measured on-screen decode/performance result. The prior [Mac guide](mac-to-mac.md) records older H.264 UI smoke evidence separately.

## Physical acceptance before verified status

- Two Macs: both directions, mirror/extend, Auto/HEVC/H.264, quality switching, Intel/Apple silicon combinations, reconnect and sleep/wake. Record codec, raster, target/rendered fps and latency.
- Thunderbolt Bridge and Ethernet: Wi-Fi enabled concurrently, verify the active interface, candidate appearance, unplug/replug, manual opt-out and no duplicate sessions. Include a normal routed/static-IP network and confirm it remains a normal LAN device.
- Pencil: supported iPad/Pencil pairs and a tablet-aware drawing app; light/heavy pressure, tilt in four directions, hover enter/exit, palm contact, two-finger scrolling, rotation, drawing while disconnecting/backgrounding and old-sender compatibility. Confirm no held mouse button or proximity state after cancellation.
- Run 30-minute and 2-hour endurance tests before making performance/release claims. Record failures and device/OS/transport details without committing private identifiers or captures.

## Source update after p8

The source adds iOS HEVC and Apple high-refresh negotiation; see [Apple video and verification](apple-video.md). The p8 download retains the earlier iOS H.264 / Mac 60fps behavior described above.

The source also adds opt-in [Mac wired / Wi-Fi handover](mac-lan-handover.md); p8 still uses the manual cable-switching behavior above.

Current source adds [advanced Pencil rotation, eraser tools and configurable gestures/shortcuts](pencil-advanced.md) over authenticated connections. The published p8 behavior described above remains unchanged.

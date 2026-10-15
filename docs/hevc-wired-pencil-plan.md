[English](hevc-wired-pencil-plan.md) | [简体中文](hevc-wired-pencil-plan.zh-CN.md)

# Mac HEVC, wired discovery and Apple Pencil

Design baseline: 2026-10-16, main `0899f01`. Source development only; published downloads remain unchanged.

## Scope and resolution behavior

The quality picker already changes the encoded raster (50%, 75%, 100%; gaming 75%) by rebuilding sessions. The extended desktop keeps receiver-derived logical dimensions. A separate per-device 1080p/1440p/4K desktop-mode picker is outside this iteration.

Implement three independently reviewable rounds, followed by a full regression and evidence update. Preserve service name, framing, preferences, role exclusivity, Android DWV2 and release identities. No remote shutdown, new public release or simultaneous two-way video is included.

## 1. Mac HEVC

Advertise HEVC only when VideoToolbox reports hardware decode support; select it only with receiver advertisement, sender hardware encode support and a compatible codec preference. Legacy peers and explicit H.264 remain H.264. Retain the existing 4096×2304 landscape / 2304×4096 portrait, 60 fps ceiling. Fit the selected HEVC operating point inside an H.264 fallback envelope so fallback never increases decoder requirements.

Use explicit streamConfig codec state, bounded Annex B parsing, HEVC VPS/SPS/PPS and IRAP recognition. Clear parameter sets and wait for a keyframe on every configuration. Validate both announced and bitstream dimensions. A HEVC format/decoder failure requests codecFailure once per connection; suspend video until a valid H.264 configuration arrives, with a bounded fallback wait. Sender initialization/runtime failures use the existing H.264 fallback. Do not change iOS video decoding in this round.

Acceptance: pure negotiation tests cover legacy, override, hardware unavailable and fallback envelopes; real VideoToolbox samples exercise H.264 and HEVC network reception where hardware exists; malformed NALs/configurations, codec reset, failed fallback and reconnect are bounded. Mac builds for arm64 and x86_64.

## 2. Direct-cable discovery

Recognize Mac Bonjour results on wired interfaces with nonempty, exclusively link-local IPv4/IPv6 addresses; exclude internal anpi interfaces and loopback. Strictly parse addresses including IPv6 zones. This is a **candidate heuristic**, not proof of physical cabling or authentication: a DHCP-less Ethernet segment can look the same. Thunderbolt Bridge or a working Ethernet link must exist; an ordinary USB-C cable alone is insufficient. Routed/static-IP Ethernet still works through normal LAN discovery without this candidate label.

Use NWParameters.requiredInterface for candidate connections, show the selected interface in session status, and do not silently route a failed cable connection over Wi-Fi. Keep normal LAN selection available when the cable is absent. Offer an explicit, default-off auto-connect preference for direct-link Mac candidates. Once enabled, allow one attempt per appearance, respect manual disconnect opt-out, autostart, transport selection and exclusive roles. Match the same installation ID before making a second session, including before hello arrives. Do not hand over an active Wi-Fi session automatically. Phone USB/ADB behavior stays unchanged.

Acceptance: policy tests cover addresses, interface filtering, identity, arrival/reappearance, manual opt-out and no repeated retry. Review interface pinning in the actual connection factory; build desktop UI. Physical acceptance covers Thunderbolt Bridge and Ethernet with Wi-Fi also enabled, disconnect/replug and reversed sender/receiver roles.

## 3. Apple Pencil

The iOS hello advertises inputCaps pencil-v1. A capable Mac responds with inputConfig; every iOS connection starts in legacy touch mode until that response. New Pencil input includes normalized position, pressure, altitude/azimuth and proximity; unsupported peers receive ordinary touch messages. Finger scrolling remains separate and palm input is suppressed during Pencil contact. Send real coalesced samples with a per-event cap; do not commit predicted samples. Support hover where UIKit/hardware provides it; barrel roll, squeeze, double-tap mapping and application-specific brush behavior are outside this version.

Validate finite/ranged peer fields before CoreGraphics conversion. Inject public tablet point/proximity fields, preserving accessibility checks and a testable event sink. Cancel pressure and exit proximity on disconnect, replacement, role change, UIKit cancellation, background or view removal. Bound iOS outbound control work and scope completion callbacks to the owning connection. Overflow closes that session so the Mac releases any held input; a stale completion must not affect a new peer.

Acceptance: capability and legacy tests; pressure/tilt bounds and malformed input; event-field tests using an in-memory sink (no desktop events); down/move/up/cancel/proximity lifecycle; bounded control admission with generation tests; iOS Simulator build and Mac builds. Actual pressure, hover/palm rejection and drawing-app behavior require an iPad and Pencil and must not be claimed from simulation.

## Upstream provenance and integration

Adapt selected GPL-3.0 implementations from peetzweg/opendisplay: `91ca272` (HEVC), `42ad6fb` and helper introduced with `d2dfb3f` (direct cable), `da9f369` (Pencil). `1c857a4` only updates release metadata. Upstream inspected at `b9eec1f232fb5ea571c87e8392379a84f47b237f`; avoid broad merges that replace DisplayWeave recovery, signing or UI. Local safety and negotiation contracts take precedence.

## Delivery and evidence

Commit this design first. Each implementation round adds behavioral regression coverage, runs affected checks and commits. Finish with all Swift suites, both Apple builds, Android tests/build, web build, bilingual docs and release consistency. Record exact results and hardware skips separately in a final evidence section. Push the review branch to displayweave; main integration follows repository review rules. Existing authorization to bypass review for PR #11 does not apply to this change.

## Execution record

Design recorded before implementation. Implementation and verification results will be appended as each round completes.

- Round 1: implemented hardware-gated Mac HEVC, bounded bitstream parsing and one-shot timed H.264 fallback. All 33 Swift suites passed, including real H.264/HEVC encoded samples, loopback codec switching and fallback timeout. Unsigned macOS arm64 + x86_64 build passed. No physical two-Mac performance claim.

- Round 2: added strict wired/link-local Mac candidate discovery, interface-pinned Bonjour/TCP, candidate/interface UI, default-off auto-connect and installation-ID deduplication before hello. Direct-link policy tests and unsigned arm64 + x86_64 builds passed. No Thunderbolt/Ethernet peer was connected for physical validation.

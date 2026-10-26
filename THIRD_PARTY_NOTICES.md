# Third-Party Notices

DisplayWeave is an independent community project derived from OpenDisplay and
informed by other open-source display-streaming projects. This file records the
primary upstream sources relevant to the repository.

## OpenDisplay

- Project: OpenDisplay
- Source: https://github.com/peetzweg/opendisplay
- License: GNU General Public License v3.0

DisplayWeave retains OpenDisplay's Git history, applicable copyright notices,
and GPL-3.0 licensing requirements. The repository root `LICENSE` contains the
license text governing the current DisplayWeave work. OpenDisplay is the source
project; DisplayWeave is independently named and maintained rather than
presented as an official OpenDisplay distribution.

The Mac-to-Mac LAN implementation selectively adapts upstream commit
`b9eec1f232fb5ea571c87e8392379a84f47b237f` (receiver originally introduced in
`23b62b3`). Specifically, `Shared/StreamReceiver.swift`, `Shared/Protocol.swift`
and the video view in `MacReceiver/MacReceiver.swift` inform
`Mac/Receiver/StreamReceiver.swift`, `ReceiverWireProtocol.swift` and
`ReceiverVideoView.swift`. Local changes gate HEVC on hardware support with H.264 fallback, add bounded
framing, exclusive sessions, lifecycle isolation, and integration with the
DisplayWeave role UI. These adaptations remain GPL-3.0. The complete upstream
history has not been merged; the assessment is recorded in
`docs/reference/mac-to-mac-design.md`.

The 2026-10-16 source upgrade also adapts failure/retry handling from
`87b000b` / `c27e538`, deferred touch-down semantics from `04590ed`, and bounded
logging from the design in `19481a6`. Implementations and regression coverage
are local adaptations under GPL-3.0; see `docs/archive/audits/upstream-integration-2026-10-16.md`.

The follow-up HEVC/direct-link/Pencil source iteration selectively adapts
`91ca272` (HEVC parameter sets and hardware negotiation), `42ad6fb` and the
helper introduced by `d2dfb3f` (direct-link discovery, excluding remote shutdown),
and `da9f369` (Pencil tablet pressure/tilt/proximity fields). `1c857a4` is release
metadata, not the Pencil implementation. Local additions include explicit input
capability negotiation, conservative fallback envelopes, strict address parsing,
interface pinning, opt-in auto-connect, bounded controls and lifecycle tests.
See `docs/reference/hevc-wired-pencil-plan.md`. All adaptations retain GPL-3.0.

## SideScreen

- Project: SideScreen
- Source: https://github.com/tranvuongquocdat/SideScreen
- License: MIT License

SideScreen was reviewed as a technical reference for end-to-end frame-rate
configuration, HEVC use, Android high-refresh rendering, transport separation,
and performance measurement. DisplayWeave did not import the SideScreen
repository wholesale. The current high-refresh implementation was adapted to
the existing OpenDisplay architecture. If future changes copy or substantially
adapt specific SideScreen source, the corresponding MIT copyright and license
notice must be retained alongside that code and recorded here.

## Sparkle

- Project: Sparkle
- Source: https://github.com/sparkle-project/Sparkle
- License: MIT License

The macOS target uses Sparkle as a Swift Package dependency for application
update support. Sparkle's own license and notices are distributed with the
embedded framework when included in an application build.

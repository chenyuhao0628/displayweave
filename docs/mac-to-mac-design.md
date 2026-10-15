[English](mac-to-mac-design.md) | [简体中文](mac-to-mac-design.zh-CN.md)

# Mac-to-Mac LAN display design

Design date: 2026-10-15. DisplayWeave baseline: `1dbfb48`.

## Upstream merge assessment

After refreshing remotes, `git merge-tree --write-tree main origin/main` tested
OpenDisplay `b9eec1f232fb5ea571c87e8392379a84f47b237f` without changing the index
or working tree. The common ancestor is `99c342c`; the histories have 165 and
100 exclusive commits. Upstream changes 145 files, overlaps 21 local paths,
and produces 20 conflicted files.

Conflicts include the sender, app lifecycle, virtual display, iOS receiver,
project, release workflow, Fastlane, update feed, branding and website. Upstream
deleted/refactored `iOS/PhoneReceiver.swift`, which this fork still maintains.
A whole-history merge needs its own protocol, branding, signing and Android
regression effort; selecting one side of textual conflicts is insufficient.

Decision: selectively port the upstream receiver core. Retain DisplayWeave's
sender, Android protocol v2, update keys, app identity, release workflow and
website. Do not mark the entire upstream history as merged. Record the pinned
source and local modifications; retain applicable GPL-3.0 and author notices.

## Scope

- Either Mac can send or receive, with one active role at a time.
- Bonjour discovery over a shared LAN, using Wi-Fi or Ethernet.
- Mirror or extend on the sender; windowed/fullscreen reception and display selection.
- macOS 14+ on both ends; H.264 up to 60fps for the first compatibility target.
- Operate the streamed desktop with the sending Mac's keyboard and mouse.
- Preserve existing iPhone, iPad and Android connections and updates.

Simultaneous bidirectional video, cross-machine input, audio, files, Internet
traversal, dedicated Thunderbolt routing and macOS 12/13 receiver packages are
outside this implementation. 4K/5K panels scale within decoder limits. 60fps
is a configuration target, not an unmeasured performance promise.

## Architecture

`Mac/Receiver/StreamReceiver.swift` ports upstream TCP framing, H.264 decode,
video-layer presentation, cursor and telemetry into the Mac target only.
`Mac/Receiver/ReceiverWireProtocol.swift` retains the upstream wire definitions.
`Mac/Receiver/MacReceiverController.swift` owns the receiver, screen, window
and sleep lifecycle. `Mac/Receiver/ReceiverVideoView.swift` is the narrow
AppKit video/cursor host. `Mac/MacRoleController.swift` coordinates roles;
SwiftUI owns settings/status and AppKit owns the video window.
`Mac/MacReceiverPolicy.swift` isolates testable panel, stream and session rules.

Send: virtual/main display → ScreenCaptureKit → VideoToolbox → TCP.
Receive: TCP → bounded deframing → Annex B → CMSampleBuffer → AVSampleBufferDisplayLayer.

## Roles and lifecycle

Default to sending and persist an explicitly selected role. Listen only while
receiving. Disable repeated role changes during transitions: stop outgoing
sessions and discovery, release virtual displays, then start reception. Reverse
the sequence when returning to sending. Filter the local install ID during
discovery and reject a self hello. Late network/ADB callbacks cannot restart
disabled roles.

Closing the video window ends its session and returns to listening. Closing
the control window keeps the service alive; quitting releases everything.
Sleep closes the session/listener; wake restores listening so the sender can
reconnect. New sessions reset decoder, cursor and buffering; old callbacks
cannot mutate replacement sessions.

## Protocol and display compatibility

Keep `_opensidecar._tcp`, TCP 9000, four-byte big-endian lengths, JSON control
and Annex B video. Advertise `device=Mac` and both DisplayWeave legacy fields
and upstream `pv`, `videoCaps` and `panel`. Macs use legacy Apple framing;
upstream `pv=3` must never opt into Android DWV2 framing.

Negotiate Mac H.264 dimensions and frame rate against decode bounds, pixel
throughput and panel refresh. Global HEVC/120fps preferences cannot override
Mac capabilities. Preserve existing iOS/Android semantics. Include both `fps`
and `framesPerSecond` in stream configuration. Recognize `closing`, `sleeping`
and `goodbye` as intentional Mac receiver session endings.

Distinguish pixels from logical points: 1x for non-Retina Mac panels, 2x for
Retina. Stream scaling leaves desktop geometry intact. Use desktop physical
size estimates. Reannounce display selection/mode changes and rebuild the
sender's extended desktop when panel parameters change.

## Connection boundary

Receiving is explicitly enabled by the user. Serve one sender at a time and
reject extra connections while busy; the user can disconnect first. Explain
local-network/firewall access when discovery fails. Label network transport
as LAN (Wi-Fi/Ethernet).

The inherited transport is unencrypted and unauthenticated TCP for trusted
LANs. State this in the receiving UI: enabling reception permits LAN senders,
and does not constitute authenticated pairing. Do not expose remote shutdown.
Bound frames/buffers; close malformed sessions while retaining the listener.
Display-only reception needs neither Screen Recording nor Accessibility.

## Implementation sequence

1. Save merge assessment, design and acceptance criteria.
2. Add failing negotiation, panel, lifecycle and framing-boundary tests before policies.
3. Port the receiver with bounded input, session isolation and deterministic stop.
4. Add video windows, screen selection, fullscreen, sleep and exclusive roles.
5. Integrate sender negotiation, display scale and closure compatibility.
6. Update bilingual guides, provenance, build entrypoint and CI self-test list.
7. Run Swift policies/network integration, macOS/iOS builds, Android and website checks.

## Acceptance and evidence

- Role transitions never receive and send together; self-connections are rejected.
- Mac H.264 size/fps respect advertised limits; legacy iOS and Android v2 tests pass.
- TCP handles fragmentation, coalescing, invalid sizes, reconnects and stale callbacks.
- Window close, fullscreen and display selection work; receiving hides sender permissions.
- macOS/iOS builds, Android tests/build and bilingual documentation checks pass.
- Separate local automation from two-Mac evidence. Without a second Mac, do not
  claim two-machine 60fps, Wi-Fi/Ethernet or 30-minute/two-hour endurance validation.

Record implementation and validation in the user guide and delivery notes.
Unexecuted physical-device checks remain explicitly unverified.

## Implementation outcome

Development implementation and local validation completed on 2026-10-16.
See the [user guide](mac-to-mac.md) for evidence and the remaining physical
matrix. Role coordination and SwiftUI are separated into
`Mac/MacRoleController.swift` and `Mac/MacRoleViews.swift`; injected services
verify exclusivity while asynchronous cleanup is pending. Reception uses the
macOS 14+ `sampleBufferRenderer` on a serial queue. Upstream remote power,
direct-cable probing and the iOS refactor are not included.

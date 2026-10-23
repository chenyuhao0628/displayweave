[English](mac-to-mac.md) | [简体中文](mac-to-mac.zh-CN.md)

# Mac-to-Mac over a local network

v0.3.0 lets either Mac send or receive one-way extended or mirrored video. Both require macOS 14+. Two-Mac physical performance and endurance acceptance remain pending.

## Connect

1. Put both Macs on the same Wi-Fi or Ethernet LAN. Guest networks or client isolation can block discovery.
2. Select **Receive** on the receiving Mac and choose its display. Generate an invitation in **Security and pairing** and transfer it through a trusted channel.
3. Import the invitation on the sending Mac. Select **Send**, **Auto** or **LAN**, then the matching receiver. Invitations last two minutes; successful pairing retains trust.
4. Choose extend or mirror. Extend supports per-device [desktop pixels](desktop-resolution.md); arrange displays in macOS Settings. Mirror keeps source-display geometry.
5. Use the sending Mac's keyboard/mouse by default. To operate it from the receiver, enable both permissions in the [input guide](mac-receiver-input.md). Control–Option–Escape stops forwarding from the receive window.
6. Close the video window or choose **Disconnect** to end the session while remaining discoverable. **Stop receiving** closes the listener. Role changes clean up old resources before starting the replacement role.

The role persists across launches; closing the control window does not quit the app. Sleep stops reception; wake resumes an enabled listener. One sender is accepted at a time. Open settings using the gear button or Command-comma.

## Permissions and capabilities

Reception needs Local Network and incoming firewall permission, but no Screen Recording or Accessibility. Sending needs Screen Recording; injected keyboard/mouse/Pencil input also needs Accessibility. Do not disable the firewall globally.

Certificate-pinned mutual TLS is the default. Bonjour `_opensidecar._tcp` and TCP 9000 remain compatible. Old apps require an explicit unencrypted legacy choice on a trusted network; authentication failure never downgrades. See [pairing](secure-transport.md).

Hardware HEVC retains H.264 fallback. Screen, codec envelopes and pixel throughput bound requested targets up to 120fps; this is not a refresh guarantee. Decode bounds are 4096×2304 landscape or 2304×4096 portrait; larger desktops are proportionally scaled for encoding. See [Apple video](apple-video.md).

Thunderbolt Bridge or link-local Ethernet can provide interface-pinned candidates; [wired/Wi-Fi handover](mac-lan-handover.md) starts off. Ordinary USB-C cabling alone does not create networking. Audio, simultaneous two-way video and Internet traversal are outside this feature. Extend relies on private `CGVirtualDisplay` behavior.

## Verification

The complete [development gate](development.md) passed; see [release evidence](release-notes-v0.3.0.md). Automated checks exercise policies, real TLS, synthetic video, input consent and stale-session isolation, but do not prove two-Mac latency or sustained high refresh. Physical acceptance still covers both directions, extend/mirror, Wi-Fi/Ethernet, Retina, sleep/wake, input and 30-minute/2-hour endurance. Interactive virtual-display tests require a verified independent online display; otherwise SKIP.

## Historical validation of the earlier implementation (2026-10-16)

Environment: Apple Silicon, macOS 26.5.2, Xcode 26.6.

| Check | Result |
| --- | --- |
| Swift policy/network/lifecycle self-tests | 26 suites passed, including existing iOS/Android protocol checks |
| macOS Debug build | Passed; arm64 and x86_64 slices both built and confirmed |
| iOS Simulator build | Passed |
| Android `test assembleDebug` | Passed |
| Website build, bilingual pairs and release links | Passed |
| Actual development app receive window | Synthetic four-color H.264 video rendered over local loopback |
| AppKit lifecycle tests | Window open/close, enter/exit fullscreen, simulated sleep/wake notifications and listener cleanup passed |
| Virtual display runtime checks | 800×600-point 1× and 2× modes and release passed |

Role tests hold cleanup pending and verify the new role cannot start early.
Network tests use a random loopback port and cover one sender, invalid frames,
reconnect and stop/restart isolation. These checks do not constitute two-Mac
validation. Intel was compiled only; macOS 14/15 runtime, real sleep/wake,
multiple-display switching, two-machine Wi-Fi/Ethernet performance and long
endurance still require physical acceptance testing.

During a later rerun the host lid was closed and its built-in display went
offline, leaving only test virtual displays. The removal check then failed;
this does not establish a code root cause. The interactive test now requires an
independent active display and otherwise reports SKIP. The 1×/2× pass evidence
above comes from earlier lid-open runs; clamshell/headless operation remains
unverified. If test displays remain listed after closing the lid mid-test,
restore a physical display before inspecting the list; do not count that state
as successful release validation.

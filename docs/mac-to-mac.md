[English](mac-to-mac.md) | [简体中文](mac-to-mac.zh-CN.md)

# Mac-to-Mac over a local network

This feature is in the source development build. The published `v0.2.1-p6`
assets do not include it. Both Macs need this build and macOS 14 or later.
Either Mac can send or receive; each runs one role at a time.

## Connect

1. Connect both Macs to the same LAN using Wi-Fi or Ethernet. Routers with
   client isolation or separate guest networks may block discovery/connections.
2. On the receiving Mac, open DisplayWeave and select **接收屏幕** (Receive).
   Reception starts when you select this role. Choose its advertised name and
   receiving display; enable fullscreen if desired.
3. On the sending Mac select **发送屏幕** (Send), choose **Auto** or **局域网**
   (LAN), and select the receiving Mac in the device list. Choose extend or
   mirror using the sender's existing mode control. USB-only mode excludes LAN.
4. For extend, arrange the new display in macOS System Settings → Displays.
   Use the sending Mac's keyboard and mouse. Receiving is display-only.
5. Close the video window or click **断开连接** (Disconnect) to end a session
   while remaining discoverable. **停止接收** (Stop receiving) closes the listener.
   Switching back to Send stops reception before enabling sender discovery.

The selected role persists across launches. Closing the control window keeps
the selected role active. Quitting ends it. Sleep closes reception; wake resumes
listening if reception was enabled. Reconnect from the sender after wake.
Only one sender is accepted; extra connections are rejected until disconnected.

## Permissions and limits

Allow Local Network access and incoming firewall connections when macOS asks.
Receiving does not need Screen Recording or Accessibility. Sending needs Screen
Recording; display-only Mac reception does not need remote-input Accessibility.
Do not use broad firewall disabling as a discovery workaround.

The inherited transport is **unencrypted, unauthenticated TCP** for trusted
LANs. Turning on reception lets LAN senders connect; there is no pairing code or
authenticated approval. Bonjour uses `_opensidecar._tcp`; video/control use TCP
9000. No remote shutdown action is offered.

Mac reception uses H.264, at most 60fps, with a 4096×2304 landscape decode bound
(or 2304×4096 portrait). A larger desktop is proportionally scaled for transmission.
Desktop geometry retains the receiving display's logical points and 1×/2× scale.
A global HEVC or 120fps preference does not override these Mac limits. The fps
label counts frames submitted to the display renderer; it is not a measured
on-glass refresh guarantee. iOS/Android capability negotiation remains separate.

Audio, keyboard/mouse forwarding from receiver to sender, simultaneous two-way
video, Internet traversal, and a dedicated USB/Thunderbolt connection mode are
outside this feature. Ethernet is part of LAN mode. Private `CGVirtualDisplay`
API remains an OS compatibility risk for extend mode.

## Build and validation

```bash
./script/build_and_run.sh
# Launch the development bundle in Receive with automatic outgoing connections off:
./script/build_and_run.sh --verify -macRole receiver -autostart NO
./tools/run-swift-self-tests.sh
# Interactive desktop checks briefly create/remove test windows and virtual displays:
./tools/run-mac-receiver-window-test.sh
```

The script generates the Xcode project and builds an ad-hoc signed Debug app
with its own bundle ID. Codex's Run action uses this same script.
The network self-test uses a random loopback port without Bonjour advertisement;
it checks hello, busy rejection, real VideoToolbox H.264 parameter sets, malformed
lengths, reconnect, disconnect, and stop/restart isolation. Policy tests check
5K scaling, 1× geometry, codec/fps limits and fragmented/coalesced framing.

Two physical Macs still need to be tested for both directions, extend/mirror,
Wi-Fi/Ethernet, Retina/non-Retina, display changes, sleep/wake and 30-minute /
2-hour endurance. Automated local tests do not establish LAN latency or sustained
60fps. Record hardware, OS, resolution, codec, transport and observed rendering
results before making performance claims.

See the [design and upstream assessment](mac-to-mac-design.md).

## Local validation on 2026-10-16

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

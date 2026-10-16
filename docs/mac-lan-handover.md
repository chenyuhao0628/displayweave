[English](mac-lan-handover.md) | [简体中文](mac-lan-handover.zh-CN.md)

# Mac wired / Wi-Fi handover

Implemented in source after p8; not included in the currently published p8 download. Two-Mac physical acceptance remains pending.

## Use

In Settings → General, enable **Mac 有线／无线自动切换** and choose **Auto** transport. The preference is off by default and separate from **自动连接直连 Mac**, which connects idle devices on appearance. LAN-only and USB-only modes do not perform automatic Mac handover. `-autostart NO` disables both automatic behaviors.

Connect to a Mac receiver normally. Once its hello confirms the same installation ID advertised by Bonjour, a direct-link candidate present for at least two seconds can replace the LAN connection. The old capture, virtual display, startup and transport cleanup complete before the new connection opens. The new Bonjour endpoint and TCP path use the selected interface; its name appears in the session row. Switching interrupts the picture and can rebuild the extended desktop.

After an unexpected connection failure exhausts the sender's existing 10-second grace, Auto can recover over another interface advertising that same Mac installation ID. A failed direct interface is excluded for that recovery sequence, even if discovery later relabels it as ordinary LAN; Wi-Fi is preferred over ordinary routed Ethernet fallback. No candidate with a different or missing ID is used. Installation IDs are routing evidence, not cryptographic authentication; the current inherited transport still requires a trusted LAN.

## Bounds and controls

- Recovery has five rounds after delays of 0.5, 1, 2, 4 and 8 seconds; each attempt waits at most five seconds for a matching Mac hello. TCP connect alone is insufficient. Lack of a candidate also consumes a round.
- Upgrades have a 15-second cooldown. At most three automatic transitions per peer occur in a 60-second window; repeated failure or recovery exhaustion suppresses further automatic work until an explicit manual connection or app restart.
- Policy state holds at most 256 peer identities; at most 32 peer transitions run at once. Existing Android USB recovery retains its separate behavior.
- **取消恢复**, **全部断开**, manual disconnect, role changes and transport-setting changes cancel pending work. A receiver's explicit exit does not initiate handover. Stale tasks and old-session callbacks cannot start a replacement or update its state.
- After cancellation/exhaustion, check the receiver, cable/bridge or Wi-Fi, then use **连接**. The original idle-device auto-connect option also respects manual opt-out.

Direct-link classification remains a link-local wired heuristic: a DHCP-less switch can look like a dedicated cable. An ordinary USB-C cable does not create networking by itself. See [direct-link setup](hevc-wired-pencil.md).

## Verification and physical acceptance

Policy and runner tests cover same-ID selection, stable arrival, cooldown/flapping, bounded state/retries, manual opt-out, stop-before-start, cancellation and generation changes during a wait. Mac universal Debug and the complete Swift self-test gate pass. These tests do not capture the desktop, create a virtual display or prove physical network handover.

On two Macs, test both directions: Wi-Fi → bridge/Ethernet arrival; unplug with Wi-Fi remaining; failed wired candidate with successful Wi-Fi fallback; Wi-Fi unavailable; rapid replug; receiver exit; cancel during cleanup/hello wait; role/transport changes; and manual reconnection after exhaustion. Confirm only one sender pipeline per receiver, no held input, interface labels and old display removal. Record the interruption and reconnect time, resolution and codec without calling it seamless or verified before measurement.

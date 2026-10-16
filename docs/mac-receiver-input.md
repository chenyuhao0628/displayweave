[English](mac-receiver-input.md) | [简体中文](mac-receiver-input.zh-CN.md)

# Mac receiver keyboard and mouse

Included in v0.3.0-preview.1. Implementation and evidence are tracked in [the feature ledger](feature-completion.md).

## Consent and scope

Both Macs must be paired over TLS. The sender explicitly permits desktop keyboard/mouse input and grants Accessibility; the receiver explicitly enables forwarding. All switches start off. Only the focused receive-video window captures local events. Control–Option–Escape disables forwarding locally and releases held input. Focus loss, window close, role change, permission removal and disconnect release held keys/buttons. The receiver itself needs neither Accessibility nor global event monitoring.

Forward physical macOS key codes, modifier changes, pointer movement, left/right/middle buttons, click counts and scrolling. Text composition remains on the sending Mac, so its keyboard layout and input method apply. Clipboard, file transfer, system-wide key capture and simultaneous roles are outside this feature.

## Protocol and ownership

Advertise `mac-input-v1` in `hello.inputCaps` only on an authenticated Mac receiver. Sender `inputConfig` grants a fresh UUID `inputSession` when its local consent, Accessibility, authenticated peer and capability checks succeed. A denial carries a recoverable status. Keep `pencil-v1` negotiation and older touch/scroll wire messages compatible.

Each `desktopInput` message has the granted session UUID, a strictly increasing bounded sequence, an event kind and validated fields. Reject old grant IDs, nonfinite coordinates, invalid keys/modifiers, excessive deltas and malformed shapes. A grant change cancels the old input state before a new one starts. No keyboard/mouse events are accepted over legacy plaintext.

The receiver reserves a bounded input-send ticket before dispatch (64 queued/in-flight messages, each at most 4 KiB). Overflow disconnects the owning connection so a missing release cannot leave a key down. Tickets and grants isolate late callbacks from replacement sessions. The sender tracks at most 16 held keys and three buttons, validates sequence and bounds before generating CoreGraphics events, and deterministically releases owned state.

Pointer coordinates use the aspect-fit video rectangle, excluding black bars. Drag release outside the picture still ends the held button using a clamped coordinate. Input targets the session's captured/virtual display; geometry changes release held state before replacing the target. Local AppKit monitoring is scoped to the video window and its responder, and is removed with that view.

## Acceptance

- Strict wire decoding, capability/consent/secure gates, sequence/grant rejection and malformed numeric/key cases.
- Aspect-fit coordinates, black bars, display-edge bounds and out-of-picture release.
- Keyboard repeat, multi-button state, held-key cap and idempotent cancel using a captured event sink, never posting into the user's desktop.
- Real encrypted receiver network exercise of grant/config/reset, stale/overflow isolation and disconnect; Mac universal build.
- Physical two-Mac checks: layouts/input methods, focus switching, keyboard shortcuts, drag/scroll, permission changes and emergency escape. Automated checks cannot prove actual application behavior or latency.

## Enable and stop

On the sender, open Settings → Permissions & Diagnostics and enable **允许接收端 Mac 的键鼠回传**; grant Accessibility there. On the receiving Mac enable **从此 Mac 操作发送端** under Keyboard & Mouse, then focus the video window. The receiver toggle is session-local and starts off at app launch; sender consent is saved. The status explains missing pairing, sender consent, permission or display readiness. Press Control–Option–Escape in the receiving window to turn forwarding off. Sender consent/permission is checked on every input and at most two seconds after an idle change; OS permission withdrawal can prevent synthetic release delivery, but local held state is still cleared.

## Automated evidence

50 Swift suites passed, including strict protocol/geometry tests and captured CoreGraphics events for repeats, drag, modifier chords, bounds, malformed input, stale grants, 16-key limit, target changes and idempotent cancellation. The production Mac receiver passed real mutual-TLS input forwarding, default-off consent, release ordering, grant replacement, revocation, queue saturation and stale-ticket isolation. Universal Mac Debug and iOS Simulator builds passed. No input was posted to the user's desktop. Local-window keyboard routing and two-device application behavior remain in the physical acceptance matrix; this round did not launch the installed app.

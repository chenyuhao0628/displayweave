[English](pencil-advanced.md) | [简体中文](pencil-advanced.zh-CN.md)

# Advanced Pencil input

Included in v0.3.0-preview.1. Actual Pencil hardware and drawing-application acceptance remain pending.

## Behavior and boundaries

Negotiate `pencil-v2` in addition to `pencil-v1` on authenticated TLS sessions. A stroke keeps its negotiated protocol until it ends. Old senders retain pressure/tilt or touch compatibility. V2 adds roll in radians and a pen/eraser tool; Mac translates radians to the tablet rotation field in degrees and changes proximity type when the tool changes. Changing tools cancels an active stroke before selecting the next tool. Devices without roll data send zero.

Use UIKit Pencil interaction callbacks for double tap and squeeze, with availability checks for iOS 17.5 features. Squeeze fires once on its ended phase and ignores cancellation. Settings map each gesture to system preference, no action, pen/eraser toggle, undo/redo or one of two local sender shortcut slots. Unsupported system preferences perform no remote action. Never execute an iOS system Shortcut remotely.

Shortcut forwarding requires separate default-off sender consent, Accessibility, authenticated V2 negotiation and a fresh action grant. The receiver sends a named action, never arbitrary key codes. The sender owns the two configurable key/modifier combinations. Each command has the current grant and a strictly increasing bounded sequence; at most five accepted actions per second. Each shortcut cancels active touch/tablet input and sends a complete modifier/key-down/key-up/release sequence synchronously. Connection, target and consent changes revoke grants. Existing receiver queue admission bounds all events before dispatch.

UI states distinguish basic, advanced and shortcut authorization. Rotation/tool changes use tablet APIs but application support is not universal; shortcuts are explicit user mappings for the current foreground Mac app. Clipboard, app automation, system Shortcut execution and automatic drawing-app detection are outside scope.

## Acceptance

Strict V1/V2 parsing, invalid numeric/tool rejection, per-stroke mode lock, roll conversion, eraser proximity changes, mid-stroke cancellation, gesture resolution, shortcut grant/sequence/rate limits, defaults and revocation. Captured CGEvent tests must not inject into the user's desktop. Both Apple builds, production secure iOS runtime and UI inspection run in an isolated simulator fixture. Physical Pencil Pro/double-tap/hover support and drawing-app matrices remain separate.

## API evidence

Checked Apple documentation and installed Xcode SDK headers on 2026-10-16:

- [UIPencilInteraction](https://developer.apple.com/documentation/uikit/uipencilinteraction) and [delegate](https://developer.apple.com/documentation/uikit/uipencilinteractiondelegate).
- [UITouch rollAngle](https://developer.apple.com/documentation/uikit/uitouch/rollangle), available since iOS 17.5; unsupported models report zero. UIKit headers document radians and the wake-relative reference angle.
- [CGEvent tabletEventRotation](https://developer.apple.com/documentation/coregraphics/cgeventfield/tableteventrotation). The SDK `IOLLEvent.h` defines rotation capability `0x2000` and eraser pointer type `3`.

## Enable and configure

Pair over TLS, then open iPad settings → Apple Pencil. Choose the tool directly or map Double Tap / Squeeze. The system choice only maps the system pen/eraser toggle; color/ink palettes, previous-tool and system Shortcuts are deliberately no-ops with explanatory UI. Roll is sampled from touch and hover on iPadOS 17.5+, normalized to one turn, and remains zero on unsupported hardware. Gesture actions do not forward while the settings sheet is open or the app is inactive.

For keyboard actions, enable **允许 Pencil 手势执行快捷键** on the Mac under Settings → Permissions & Diagnostics. Grant Accessibility there. Undo is Command-Z, redo is Shift-Command-Z. Configure custom slots 1/2 with a physical Mac key and Shift/Control/Option/Command; defaults are E and B. These are foreground-application shortcuts, not universal drawing tools. Sender consent persists; grants and held input never persist. Consent/permission is checked on every action and within two seconds while idle. A revoked system permission may prevent release event delivery, but owned input state is cleared.

## Automated evidence

Strict V1/V2 and captured-event tests cover rotation conversion, eraser proximity, tool changes, malformed fields (including JSON booleans), preserved legacy strokes, gesture deduplication, permission loss, balanced shortcuts, invalid custom preferences, one-second rate limits and stale grants. The production iOS receiver passed actual mutual-TLS transmission of V2 rotation/eraser/cancel and an authorized shortcut, followed by V1 downgrade with no shortcut emission; live pairing revocation and background shutdown remain covered. The settings section was inspected in light/dark modes in the isolated iPhone simulator fixture, in the disconnected state. This does not exercise physical Pencil callbacks or drawing applications.

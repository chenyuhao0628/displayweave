# Architecture

## 中文摘要

DisplayWeave 由 macOS 发送端、iOS/iPadOS 接收端和 Android 接收端组成。
Apple 接收端当前支持 USB 与 WiFi，使用 H.264；Android 当前使用 WiFi，
通过可选能力字段和 `streamConfig` 协商 HEVC/H.264、30/60/90/120fps、
分辨率与码率。HEVC 失败时自动回退 H.264，旧接收端继续走 H.264/60fps
兼容路径。Android USB/ADB reverse、加密配对和 iOS 120Hz 尚未实现。

DisplayWeave is split into sender and receiver apps. The Mac app owns display
creation, capture, encoding, transport, and input injection. Receiver apps own
device discovery, decode, presentation, and user input collection.

## System Shape

```text
Mac sender
  display source
    mirror: existing macOS display
    extend: CGVirtualDisplay
  capture: ScreenCaptureKit
  encode: VideoToolbox H.264 or HEVC (capability-negotiated)
  transport: length-prefixed TCP
  input: CGEvent injection

iOS receiver
  transport: Network.framework listener
  decode/render: AVSampleBufferDisplayLayer
  input: UIKit touch events

Android receiver
  discovery: Android NSD
  transport: WiFi TCP ServerSocket
  decode/render: H.264 or HEVC via MediaCodec + SurfaceView
  input: Android touch events
```

## Data Flow

1. The receiver advertises or listens on port `9000`.
2. The Mac discovers an Apple receiver through USB or WiFi, or an Android
   receiver through WiFi.
3. The receiver sends a JSON `hello` message with display, device, codec, and
   frame-rate capability metadata where supported.
4. The Mac chooses mirror or extend mode.
5. The Mac captures frames and encodes H.264 for Apple/legacy receivers. For a
   capable Android receiver, it sends `streamConfig` and may select HEVC plus a
   negotiated 30/60/90/120fps target, with automatic H.264 fallback.
6. The receiver decodes and presents frames.
7. The receiver sends touch, scroll, ping, and keyframe-control JSON messages.
8. The Mac maps input onto the active display and injects macOS events.

## Transport

Current transport support is platform-specific:

| Receiver | USB | WiFi |
| --- | --- | --- |
| iPhone / iPad | Supported through macOS `usbmuxd` | Supported through Bonjour + TCP |
| Android | Not implemented; ADB reverse is planned | Supported through Android NSD + TCP |

All receiver payloads use the same frame format:

```text
[4-byte big-endian length][payload bytes]
```

Payload types:

- H.264 or HEVC Annex B video frame data, selected by receiver capability
- JSON control messages such as `hello`, `streamConfig`, `codecFailure`,
  `touch`, `scroll`, `ping`, `pong`, `kf`, `cursor`, and `cursorImg`

This keeps the protocol simple enough for iOS and Android to share one sender
implementation, while still allowing platform-specific receiver internals.

## Capability Negotiation And Stream Configuration

New Android receivers add optional fields to `hello`, including display refresh
information, maximum FPS, codec support and preference, device metadata, and
transport. The Mac applies `RefreshRatePolicy` and `StreamEncodingPolicy` to
select a supported 30/60/90/120fps target, codec, bitrate, and display mode.

Before video frames, the Mac sends an optional JSON `streamConfig` containing
the selected codec, FPS, dimensions, bitrate, and transport. Android uses it to
configure `MediaCodec`, frame timestamps, and the preferred display mode. HEVC
is selected only when the receiver reports usable support. Encoder setup,
runtime encoding, or Android decoder failures trigger `codecFailure` handling,
an H.264 rebuild, a new `streamConfig`, and a forced keyframe.

Receivers that omit the new capability fields continue on the legacy
H.264/60fps path. Unknown JSON fields and optional messages are ignored where
possible, so protocol additions remain backward-compatible rather than
creating an Android-only replacement protocol.

## Mac Sender

Important responsibilities:

- discover Apple receivers over USB or WiFi and Android receivers over WiFi
- create or select the display source
- keep virtual-display geometry in sync with receiver dimensions
- capture via ScreenCaptureKit
- encode with low-latency H.264 or HEVC settings and fall back to H.264 when
  HEVC setup or runtime encoding fails
- apply backpressure and request keyframes when needed
- inject touch and scroll input through Accessibility APIs
- expose user-facing state in the SwiftUI app

The Mac app needs Screen Recording for capture and Accessibility for injected
input. Local Network permission is needed for WiFi discovery.

## iOS Receiver

The iOS receiver is the original receiver target. It keeps the app in the
foreground, listens for the Mac, renders H.264 frames, and sends UIKit touch
events back as normalized control messages. Its protocol path remains
compatible with OpenDisplay while DisplayWeave evolves Android capability
negotiation independently.

## Android Receiver

The Android receiver mirrors the iOS receiver contract while using Android
platform APIs:

- `NsdAdvertiser` publishes `_opensidecar._tcp`
- `OpenDisplayServer` owns the TCP server and stream loop; the legacy class name
  is retained as an internal compatibility identifier
- `H264SurfaceDecoder` manages both AVC and HEVC `MediaCodec` sessions; its
  legacy class name does not describe the full current codec support
- `CursorOverlayView` draws the Mac cursor above the video surface
- `TouchGestureCoordinator` maps tap and drag gestures
- `ScrollGestureTracker` maps two-finger scroll
- `DisplayProfile` controls the advertised resolution profile

Android control writes are kept off the UI thread to avoid runtime crashes.
Android currently has no USB/ADB reverse transport; that remains planned work.
The high-refresh path is experimental and has measured about 109-111 FPS on the
validated OnePlus 120Hz device, not a guaranteed sustained 120 rendered FPS.

## Queueing, Metrics, And Latency

The sender and Android receiver favor recent frames over accumulating latency.
The Mac limits pending sends; Android classifies keyframes and parameter sets,
keeps a bounded latest-frame-oriented decode queue, and requests a keyframe
when recovery requires one. Codec configuration and sync frames are preserved
when ordinary frames are dropped.

Runtime telemetry reports requested and selected settings plus capture,
encode, send, receive, decode, and render rates. It also exposes queue depth,
drops, bitrate/frame size, and available latency or frame-age measurements.
These measurements are the acceptance signal: requesting a 120fps stream or
activating a 120Hz Android display mode is not proof of sustained 120 FPS.

## Design Constraints

- The system is local-first and should not require external servers.
- The sender should not grow Android-only assumptions when capability
  negotiation can preserve iOS compatibility.
- Any new protocol field should be optional or versioned.
- Display and input changes should be verified in mirror and extend modes.
- Build artifacts, generated projects, and APK outputs should stay out of Git.

## Risk Areas

- `CGVirtualDisplay` is a private macOS API and can change across macOS updates.
- WiFi transport is latency-sensitive and can be affected by routers, VPN TUN
  mode, multicast filtering, and Android vendor networking behavior.
- Android hardware decoders differ by device.
- Accessibility and Screen Recording permissions fail silently in some macOS
  states, so user-facing diagnostics matter.

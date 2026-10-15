[English](ARCHITECTURE.md) | [简体中文](ARCHITECTURE.zh-CN.md)

# DisplayWeave Architecture

## System shape

DisplayWeave consists of a macOS sender and Apple/Android receiver applications. The Mac creates a virtual display with `CGVirtualDisplay`, captures it with ScreenCaptureKit, encodes it with VideoToolbox, and sends framed video over a direct local TCP connection. Input and receiver telemetry travel back on the same session.

Each connected device owns an independent sender pipeline and benchmark recorder. Runtime bitrate changes update VideoToolbox rate-control properties without rebuilding the encoder. Auto bitrate consumes per-session queue, drop, RTT, and frame-age evidence; send-queue and GOP policies remain bounded by quality and transport. Target bitrate is configuration intent, while actual bitrate is measured throughput.

```text
macOS virtual display
  -> ScreenCaptureKit
  -> VideoToolbox H.264 / negotiated HEVC
  -> framed TCP session
     -> Apple receiver (usbmuxd USB or WiFi, H.264)
     -> Android receiver (ADB-forward USB or WiFi, HEVC/H.264)
  <- touch, scroll, codec status, metrics, lifecycle messages
```

## Discovery and identity

Apple and Android WiFi receivers advertise the inherited `_opensidecar._tcp` Bonjour/NSD service for compatibility. An install ID identifies a receiver application instance across transports. Compatibility names such as `OpenSidecar.xcodeproj`, bundle IDs, Java package names, preference keys, and service names are migration-sensitive contracts, not current public branding.

## Android USB

The Mac locates ADB from an explicit preference, `PATH`, Android SDK environment variables, the default macOS SDK, or Homebrew. It parses `adb devices -l` and admits only rows in `device` state with wired `usb:` metadata. Wireless-debugging endpoints are excluded.

For every wired serial, the Mac allocates an unused loopback port and runs:

```text
adb -s <serial> forward tcp:<dynamic-local-port> tcp:9000
```

Each `DeviceSession` owns and removes only its own mapping. DisplayWeave never uses `adb forward --remove-all`. USB reuses the normal framed protocol, stream configuration, codec negotiation, input, and metrics path.

## Auto handover

Auto prefers USB. A protocol-level grace period and bounded 0.5/1/2/4/8-second recovery sequence run after failure. When exhausted, Auto may accept only the WiFi receiver with the same install ID. If USB returns, the same-install-ID WiFi session ends before USB connects, preventing the single-client Android receiver from being contested by two Mac sessions.

## Codec and frame-rate negotiation

Legacy Apple receivers use H.264. Android advertises codec and refresh capabilities, accepts `streamConfig`, and prefers HEVC when both sides support it. Codec failure produces a control message and falls back to H.264. Android negotiates 30/60/90/120fps targets and requests a compatible display mode; requested FPS is not proof of rendered FPS.

All peers retain the outer four-byte network-order frame length. Legacy iOS and non-negotiated Android frames use the JSON telemetry prefix plus Annex-B payload. Only Android peers that independently advertise `binaryFrameHeaderV2` receive the fixed `DWV2` identity/timestamp/flags header; the receiver then hands an offset/length view of the original bounded transport array to MediaCodec. See [the binary-header and allocation contract](docs/android-binary-frame-header-v2.md).

## Lifecycle and input

The Android receiver owns a TCP server on port 9000 and restarts idempotently when the rendering surface returns. On reconnect, the Mac resends stream configuration before requesting a keyframe and treats a peer protocol message—not only TCP connect—as readiness.

Touch coordinates, drag state, cursor movement, and two-finger scroll are encoded as control JSON and injected on macOS. Accessibility permission is required for input injection.

## Security boundaries

- WiFi TCP is not production-encrypted; use a trusted LAN.
- ADB RSA authorization trusts the Mac as a debugging host beyond DisplayWeave.
- The macOS Preview is ad-hoc signed and not notarized.
- The Android APK uses an offline project keystore stored outside Git.
- The iOS public artifact is an unsigned re-signing input.
- `CGVirtualDisplay` is a private API and can change across macOS releases.

See [SECURITY.md](SECURITY.md) and [docs/README.md](docs/README.md).


## Mac receive role (development build)

The Mac app switches between sending and receiving. Receiving stops sender sessions
and discovery, then uses an independent TCP listener, bounded deframing and
AVSampleBufferDisplayLayer H.264 rendering. One sender is accepted at a time; stale
connection callbacks cannot mutate replacement sessions. The sender respects logical
points, display scale and codec size/fps limits. Mac uses legacy Apple framing, not
Android DWV2. See the [design](docs/mac-to-mac-design.md).

## Source ownership and bounded work (2026-10-16)

The source app supports exclusive Mac send/receive roles over the same Wi-Fi or Ethernet LAN. This remains a development feature beyond the v0.2.1-p6 downloads. Mirroring captures an existing display; extending creates a virtual display.

| Area | Ownership |
| --- | --- |
| Mac presentation | `OpenSidecarMacApp`, `MacRoleViews`, `SenderWorkspaceView`, `SenderSettingsView`, `SessionRow`, `UpdateViews`; `SettingsWindow` narrowly hosts the desktop settings window. |
| Mac sessions | `SenderController` owns discovery and replacement barriers; each `DeviceSession` owns a sender and `SessionLifetime`. Startup failure and stop release resources before a replacement starts. |
| iOS presentation | `ReceiverScreen`, `ReceiverIdleView`, `ReceiverOnboardingView`, `ReceiverSettingsView`, `ReceiverPerformanceView`, `ReceiverModel`, `ReceiverVideoView`. |
| Shared Apple boundaries | `Shared/ReceiverFrameDecoder` validates legacy lengths (16 MiB maximum); `ReceiverCursorImage` checks bytes and pixel geometry before decoding; `BoundedLogWriter` limits files and queued work. |
| Android presentation | `ReceiverUi` owns shared styles; `ReceiverActivity` owns connection/lifecycle presentation. |
| Website | Shared CSS tokens and semantic React sections; server rendering and client hydration share the same tree, with generated bilingual-page checks. |

`PhoneReceiver` owns listener/connection state on its serial queue and ignores stale callbacks. Backgrounding detaches the old socket before a best-effort goodbye. Android control writes have one worker, 128 queued tasks and a 64 KiB payload limit; readers have two workers and two queued tasks. Saturation disconnects the affected session so input cannot accumulate without bound. Sender geometry and input are validated before arithmetic and CoreGraphics conversion.

See the [UI contract](docs/ui-guidelines.md), [development commands](docs/development.md), and [source audit with verification limits](docs/source-upgrade-audit-2026-10-16.md).

[English](https://github.com/chenyuhao0628/displayweave/blob/main/docs/release-notes-v0.2.0-preview.3.md) | [简体中文](https://github.com/chenyuhao0628/displayweave/blob/main/docs/release-notes-v0.2.0-preview.3.zh-CN.md)

# DisplayWeave `v0.2.0-preview.3` release notes

[GitHub prerelease](https://github.com/chenyuhao0628/displayweave/releases/tag/v0.2.0-preview.3)

## Android connection recovery

- A dedicated accept loop lets a new WiFi or ADB-forwarded socket immediately
  replace a blocked or half-open predecessor.
- Connection Generation isolates stale reader, writer, decoder, error, and
  disconnect callbacks so an old connection cannot stop the current stream.
- TCP no-delay and keepalive are enabled, while application recovery remains
  bounded and observable through the receiver connection-state model.
- Android background and surface closure retain the existing finite reconnect
  grace. A legacy Apple Receiver clean exit still ends its session immediately.

## Negotiated Android Protocol V2

- Android advertises StreamConfig Ack, Decoder Ready, First Frame Rendered,
  Session Epoch, Config Version, and Frame Sequence as one complete capability
  set. Partial capability advertisements safely fall back to the legacy path.
- Mac reports Streaming only after the matching first rendered frame. Ack,
  decoder, and first-frame timeouts use two shared retries and at most one
  cross-connection retry.
- Epoch, version, and sequence checks reject stale configurations and frames
  before they reach MediaCodec or current statistics.
- Compatible bitrate-only reconfiguration reuses MediaCodec; codec, FPS, or
  dimensions changes replace it without blocking the network event executor.
- A negotiated decoder reset requests a fresh StreamConfig before the IDR, so
  the rebuilt decoder receives a new Config Version.

## Legacy compatibility

The OpenDisplay iOS Receiver continues using the existing length prefix,
legacy StreamConfig, JSON telemetry prefix, Annex-B H.264, hello, input,
ping/pong, and goodbye messages. Protocol V2 is enabled only for an Android
peer that advertises every required capability.

## Validation scope

Android's full 61-task build, all six Android self-test groups, focused Mac
protocol and transport tests, macOS Debug, unsigned iOS Simulator Debug, the
website build, bilingual documentation checks, and release-link checks passed.

A short OnePlus OPD2413 ADB USB HEVC/120 check completed Ack, Decoder Ready,
First Frame, repeated bitrate-only configurations, and competing-socket
takeover. The observed 191 ms and 218 ms StreamConfig-to-first-frame samples
are recovery observations, not same-condition performance claims. WiFi 60/120,
USB 60, old TestFlight runtime compatibility, and controlled A/B measurements
remain pending.

## Application update

Mac build 4 is offered through the EdDSA-authenticated Sparkle feed. Android
version code 4 is offered through the pinned-certificate update manifest. The
Mac app remains ad-hoc signed and not notarized; the iOS artifact remains an
unsigned re-signing input and is not automatically updated.

The release publishes `DisplayWeave-macOS.dmg`, `DisplayWeave-macOS.zip`,
`DisplayWeave-Android.apk`, the unsigned iOS re-signing input, signed update
feeds, and `SHA256SUMS.txt`. Verify the checksums from the release before use.

## SHA-256

| Asset | SHA-256 |
| --- | --- |
| `DisplayWeave-macOS.dmg` | `68b3737f09f8d02da135aef89167896aa4057d453d65fa20861e2ae58a142a29` |
| `DisplayWeave-macOS.zip` | `32cade719d825d3f3562483cb72b9a4d65223e4b2518d54389ff2d661a1742ae` |
| `DisplayWeave-Android.apk` | `98356346793932bd494a31585ff7ca788b880bd62cd6b8e2762aadc8ff0541c1` |
| `DisplayWeave-Preview-0.1-iOS-unsigned-resigning-input.ipa` | `7eb93eedd24e44bbabccb38ab145a2e2122e4c53bd52dbe8e9d2b3d08e21eb16` |
| `appcast.xml` | `3606e4f32678319f1bcea1e94e97bcba1a1171a6810ed935be3b00264f4795c8` |
| `android-update.json` | `90adbfe6345de384c8541b986673cae28c256a6cef8017e000fb93ff7cfdbf70` |

[English](https://github.com/chenyuhao0628/displayweave/blob/main/docs/release-notes-v0.2.1-p3.md) | [简体中文](https://github.com/chenyuhao0628/displayweave/blob/main/docs/release-notes-v0.2.1-p3.zh-CN.md)

# DisplayWeave `v0.2.1-p3` release notes

DisplayWeave 0.2.1-p3 improves high-refresh streaming and connection recovery on macOS and Android.

## Changes

- Separates asynchronous VideoToolbox encode work from socket-send backpressure so 90/120fps capture is no longer incorrectly capped near 60fps.
- Correctly labels the active USB or WiFi transport in stream configuration.
- Makes the selected transport mode determine which device target the Connect button uses.
- Reclaims stale DisplayWeave-owned ADB forwards before reconnecting and prevents Android main-thread disconnect handling from blocking on WiFi output.
- Expands and centralizes the bounded Android server/decoder frame queues to absorb short scheduler and transport bursts.
- Compiles the animated performance test pattern only in Debug builds; Release artifacts contain only a no-op contract.

## Validation

- All 22 macOS standalone self-test suites pass.
- macOS Release builds successfully for arm64 and x86_64.
- Release binary audit finds no animated test-pattern view, log strings, or CoreVideo display-link entry points.
- Physical-device USB and WiFi H.264/HEVC tests cover 60/90/120fps modes on the available OnePlus Android device.
- `git diff --check` passes.

High-refresh performance remains hardware- and network-dependent. WiFi reference-chain recovery can still cause short frame-rate dips.

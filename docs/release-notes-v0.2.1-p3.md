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

## SHA-256

- Android APK: `99bdedb0743eb34cc7d2cb94aaa4141e8d9542e0fd4a42460ae46fccc4904004`
- macOS ZIP: `d925d89c4cae6db1723abedf322afd97d414a9c2f985a64516b647a1669b7a01`
- macOS DMG: `4d375d6cb50d5a99420a564c7f0e6f1b2231e6b67e58a4efd78d12db5b512c1e`
- iOS unsigned re-signing input: `90c971ff0837a401563a48cabfa594e86aa0ff02b513d24996a109123a5a4949`
- Sparkle appcast: `5fb508cb5dd8cfc9f4f3f01db2c799c7f9f441b5fdc1315c281e12604bb2c5a3`
- Android update manifest: `ede2c36c2f5b01fba62ae29412373d5ccda4882c6598242bb40f85b1185fbef8`

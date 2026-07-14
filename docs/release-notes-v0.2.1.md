[English](release-notes-v0.2.1.md) | [简体中文](release-notes-v0.2.1.zh-CN.md)

# DisplayWeave `v0.2.1` release notes

DisplayWeave 0.2.1 focuses on connection and decoder lifecycle correctness, bounded recovery, and reproducible release validation.

## Highlights

- Isolates every Mac `NWConnection` callback with an independent connection generation and current-object check.
- Coalesces delayed reconnect work, cancels it on readiness or shutdown, and rejects expired reconnect tasks.
- Anchors the disconnect grace period to the last peer activity so the virtual display is released around the advertised 10-second deadline instead of after two stacked timeouts.
- Isolates Android asynchronous `MediaCodec` callbacks by decoder generation, enforces input-buffer ownership, and bounds rendered-frame telemetry.
- Recognizes HEVC IRAP recovery frames including CRA and coalesces terminal decoder recovery.
- Scopes Mac asynchronous encode work to encoder generations and rejects stale or duplicate completions.
- Aligns advertised Android decoder FPS with the selected runtime decoder and its H.264 fallback.
- Reports reset-safe GC window deltas and adds CI coverage for Android, Mac, iOS compatibility, website, documentation, and release contracts.

## Validation

- 22 standalone Swift suites pass.
- Android clean tests and Debug assembly pass, including all six self-test groups.
- macOS Debug and unsigned iOS Simulator compatibility builds pass.
- Website, bilingual documentation, release-link, workflow syntax, and whitespace gates pass.

Physical WiFi/USB, codec, refresh-rate, recovery, endurance, and Legacy receiver validation remains Pending where no device was available. The Mac app remains ad-hoc signed and is not Apple-notarized; verify release checksums before installation.


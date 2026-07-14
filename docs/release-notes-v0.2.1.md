[English](https://github.com/chenyuhao0628/displayweave/blob/main/docs/release-notes-v0.2.1.md) | [简体中文](https://github.com/chenyuhao0628/displayweave/blob/main/docs/release-notes-v0.2.1.zh-CN.md)

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

- [Release workflow 29355318964](https://github.com/chenyuhao0628/displayweave/actions/runs/29355318964) built commit `80c923f` as Mac/Android build `7`, verified the complete update release, uploaded seven immutable assets, and deployed both update feeds.
- 22 standalone Swift suites pass.
- Android clean tests and Debug assembly pass, including all six self-test groups.
- macOS Debug and unsigned iOS Simulator compatibility builds pass.
- Website, bilingual documentation, release-link, workflow syntax, and whitespace gates pass.

Physical WiFi/USB, codec, refresh-rate, recovery, endurance, and Legacy receiver validation remains Pending where no device was available. The Mac app remains ad-hoc signed and is not Apple-notarized; verify release checksums before installation.

## SHA-256

- `ee507c6d3b4ddd80c7bdf3142ffe268cc06d5539950cd9298207c30de3a836fe` — `DisplayWeave-macOS.zip`
- `fc2964c6f5a7088269b5b6637db2df2d0fc3dc95abd134d427a998b8fa976fc1` — `DisplayWeave-macOS.dmg`
- `3b0d0e3be13ea195867573746cf1938bc835f654391770b7269c3fbdfbbb494a` — `DisplayWeave-Android.apk`
- `50dd56b234c54d1e57aa64e7941eb2fe88e70640a128da284decb25cb850114e` — `DisplayWeave-Preview-0.1-iOS-unsigned-resigning-input.ipa`
- `04111c2406e9efab99756604eb8bcc91abbb7a89de51117e26291f4c9a0c0cd9` — `appcast.xml`
- `b8383d74f91a066fa68734990a7250b4bc6c23d13e487035cb452c70de0f572c` — `android-update.json`

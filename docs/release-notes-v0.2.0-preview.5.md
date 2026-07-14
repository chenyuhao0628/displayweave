[English](https://github.com/chenyuhao0628/displayweave/blob/main/docs/release-notes-v0.2.0-preview.5.md) | [简体中文](https://github.com/chenyuhao0628/displayweave/blob/main/docs/release-notes-v0.2.0-preview.5.zh-CN.md)

# DisplayWeave `v0.2.0-preview.5` release notes

[GitHub prerelease](https://github.com/chenyuhao0628/displayweave/releases/tag/v0.2.0-preview.5) · [Release workflow](https://github.com/chenyuhao0628/displayweave/actions/runs/29350612086)

## High-refresh Android streaming

- The Mac now counts pending VideoToolbox encodes and network sends together, bounding end-to-end work before stale frames can accumulate in TCP.
- Android feeds MediaCodec through asynchronous callbacks and retains only the newest pending compressed frame when decoder input is unavailable.
- Decoder throughput is derived from the selected hardware codec's video capabilities and performance points instead of being inferred only from the display refresh rate.
- If an encoded reference frame is dropped, dependent frames are rejected until the next keyframe and the Mac is asked to generate that keyframe.

## Refresh-rate mapping

- A requested stream rate now selects the exact display mode when available, otherwise the next higher supported mode before falling back to the highest mode.
- On a 60/120/165 Hz tablet, a 90 FPS request therefore selects 120 Hz rather than 60 Hz.

## Build and verification

The Release workflow built target commit `4276c1a229f9f0b3237242d3ebbc0f29d7e244da` as Mac/Android build `6`. It passed the Mac Release build, unsigned iOS compatibility build, signed Android Release build, APK signer verification, complete update-release verification, upload of seven immutable assets, and Pages feed deployment.

Before publication, the change also passed the Android Debug build and six self-test groups, the Mac send-queue standalone test, an unsigned macOS Debug build, bilingual-document validation, release-link validation, and whitespace checks. Physical-device throughput and long-duration validation remain pending, so performance remains hardware-dependent.

## Distribution boundary

Mac remains ad-hoc signed and not notarized. Android is v2 signed by the pinned project certificate. The iOS artifact remains an unsigned arm64 re-signing input and is not automatically updated.

## SHA-256

| Asset | SHA-256 |
| --- | --- |
| `DisplayWeave-macOS.dmg` | `9142408567a5ca417c5c5547c7d8a53eb4b87765f369b4899a53444a96fe1316` |
| `DisplayWeave-macOS.zip` | `64b1bbe9c1a38434b9843c336e93fe9c0a6ebb23943a8cb5c6cbfd9ccffdfac8` |
| `DisplayWeave-Android.apk` | `adea5d92d8abd4e1fd97ea9bc5fbad50b4d475c3d5800e79dd5567a6ee153124` |
| `DisplayWeave-Preview-0.1-iOS-unsigned-resigning-input.ipa` | `e0bc60128b0c2f3910dd7bcb5f8d8bdc9fceb0de34965575da0902b78dc1fd00` |
| `appcast.xml` | `721354e100754baea15f352cafdbf4522b84d0f4c5e4451511df86ce03882c5b` |
| `android-update.json` | `1841ce9ba576de691b5405a1056b26d1a6053a1ffe39e30f1945a13f0992f3c3` |

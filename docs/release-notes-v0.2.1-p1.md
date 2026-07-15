[English](https://github.com/chenyuhao0628/displayweave/blob/main/docs/release-notes-v0.2.1-p1.md) | [简体中文](https://github.com/chenyuhao0628/displayweave/blob/main/docs/release-notes-v0.2.1-p1.zh-CN.md)

# DisplayWeave `v0.2.1-p1` release notes

DisplayWeave 0.2.1-p1 is a corrective update for asynchronous Android decoding, reference-chain recovery, Mac asynchronous work isolation, and USB bitrate attribution.

## Highlights

- Replaces the Android server and `MediaCodec` single-frame pending slots with small ordered queues so brief input-buffer pressure no longer immediately destroys the prediction chain.
- Enters keyframe recovery only after a predictive frame is actually lost, clears unsafe queued frames, coalesces recovery requests, and reports waiting-frame rejection separately from the first reference-chain break.
- Adds end-to-end receiver counters for received, submitted, decoded, and rendered frames; queue replacement, recovery duration, and keyframe request/receipt counts are also exported to Mac benchmarks.
- Reports the maximum FPS of the decoder that actually configured successfully and renegotiates the Mac capture rate when the runtime fallback is slower than the advertised candidate.
- Tracks VideoToolbox work by generation and unique work ID, preventing stale or duplicate completions from corrupting the current pending-encode budget.
- Exposes pending encodes, pending sends, combined work, and pending-encode peaks without changing the legacy queue-depth field.
- Uses a transport-aware USB Auto bitrate estimate. Native 3040×1904, 120 fps, High-quality HEVC starts near 112 Mbps and may recover toward the 160 Mbps USB ceiling.
- Stops treating USB encoder-side capture skips, mismatched FPS windows, or short RTT/frame-age changes as physical-link congestion. Real pending sends and sustained Android decoder pressure remain protective decrease signals.

## Validation

- All standalone Swift suites pass.
- Android clean tests and Debug/Release compilation pass, including all six self-test groups.
- macOS Debug builds successfully.
- The production website, bilingual documentation, release contract, and whitespace checks pass before publication.
- On a OnePlus OPD2413 over ADB USB with HEVC at 3040×1904 and a requested 120 fps, post-fix high-activity windows observed received/submitted/decoded/rendered counts of 72/72/72/72, 75/75/75/75, 76/76/76/76, and 81/81/80/80. Those windows reported zero pending-slot replacements, reference-chain breaks, recovery duration, and keyframe requests.

The Android high-refresh recovery fix has physical-device evidence for the configuration above. The new USB bitrate policy is covered by policy tests and build validation; a controlled same-scene USB/WiFi bitrate matrix remains pending. The Mac app remains ad-hoc signed and is not Apple-notarized.

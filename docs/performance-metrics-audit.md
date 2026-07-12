[English](performance-metrics-audit.md) | [简体中文](performance-metrics-audit.zh-CN.md)

# DisplayWeave Preview 2.x Performance Metrics Audit

Audit date: 2026-07-11

Baseline: `d5eb716`

Scope: macOS Sender and Android Receiver. This document records only semantics proven by the code. A value appearing in an overlay does not make it suitable for a formal benchmark.

## Classification

- **Measured:** derived from runtime events, byte counts, or callbacks.
- **Configured:** a requested target, not proof of what the device achieved.
- **Estimated:** depends on clocks on different devices or cannot isolate one pipeline stage.
- **Exportable:** currently available as structured CSV/JSONL. UI-only values and free-form logs are not considered exportable.
- The pipeline uses `Date` / `System.currentTimeMillis()` wall clocks rather than an end-to-end monotonic clock. Every cross-device value is exposed to system time adjustments, asymmetric paths, and clock-offset error.

## Metric matrix

| Metric | Source | Window / unit | Measurement and clock semantics | Current export | Benchmark suitability |
| --- | --- | --- | --- | --- | --- |
| Capture FPS | `capFrames` in `MacSender.stream(_:didOutputSampleBuffer:)`, divided by elapsed time about every two seconds | ~2 s / FPS | Measured on the Mac clock. ScreenCaptureKit can legitimately produce fewer callbacks for static content | No; ping/overlay and low-FPS warning only | Suitable with a fixed dynamic source after structured export |
| Encoded FPS | Counted after successful VideoToolbox completion and Annex B conversion | >=1 s / FPS | Measured on the Mac clock | Partial; Debug `ENC-STATS` text and ping | Suitable after receiver window alignment |
| Sent FPS | Successful `contentProcessed` callbacks from `NWConnection.send` | >=1 s / FPS | Local send-completion measurement; it does not prove peer receipt | No; ping/overlay only | Suitable when named as local completion throughput |
| Received FPS | Counted when Android receives a video payload and places it in the latest-frame slot | >=1 s window emitted by render callbacks / FPS | Measured on Android; no render means the window is not published | No; overlay only | Suitable after periodic structured publication |
| Decoded FPS | Decoder callback after MediaCodec dequeues an output buffer | Android metrics window / FPS | Measured on Android | No; overlay only | Suitable after export |
| Rendered FPS | MediaCodec `OnFrameRenderedListener` callback | Android metrics window / FPS | Measured callback, not proof of completed photon scanout | No; overlay only | Primary high-refresh metric after export |
| Requested FPS | `requestedCaptureFps`, ScreenCaptureKit interval, and `streamConfig.fps` | Configuration event / FPS | Configured. Android uses `streamConfig.fps` and does not parse the same field from ping | Configuration log | Test condition only, never a result |
| Actual virtual-display refresh | `CGDisplayCopyDisplayMode` when the virtual display is created | Creation event / Hz | Measured but can become stale because later HiDPI mode enforcement does not refresh the cached value | Creation log/ping | Suitable after periodic reread |
| Android actual display refresh | `Display.getRefreshRate()` | Each Android metrics window / Hz | Measured. The overlay currently shows requested surface Hz instead of this actual value | No | Suitable after display/export correction |
| Target bitrate | `StreamEncodingPolicy`, applied to VideoToolbox and sent as `streamConfig.bitrate` | Configuration event / bps | Configured; current clamps are HEVC 12–80 Mbps and H.264 8–30 Mbps | Configuration log | Test condition only |
| Actual bitrate | Wire bytes completed by send multiplied by eight and divided by elapsed time | >=1 s / bps | Measured local wire throughput, including framing, telemetry, and Annex B | Transient Mac UI only | Must be persisted; encoded-payload bitrate must be separate |
| Average frame size | Annex B encoded bytes divided by encoded frames | >=1 s / bytes/frame | Measured; excludes telemetry and framing | Debug text/ping, no CSV | Suitable if its byte scope is documented |
| Encode latency | Immediately before `VTCompressionSessionEncodeFrame` through completion | >=1 s arithmetic mean / ms | Measured API latency; not capture PTS through completion | Debug text/ping, no CSV | Rename to `encodeApiLatencyAvgMs` and add percentiles |
| Decode latency | Mac `snd` wall time through Android render wall time | >=1 s arithmetic mean / ms | Cross-clock estimate containing network, queueing, decode, and presentation; **not pure decode** | No | Current name is invalid for formal use; rename and measure MediaCodec stages separately |
| RTT | Android t1 ping, Mac pong echo, Android t2 | Most recent ~2 s sample / ms | Measured round trip on Android, but with wall-clock timestamps | No; overlay only | Suitable after sample and P50/P95 export |
| Clock offset | `Mac mt - (Android t1 + t2) / 2` | Replaced on each pong / ms | Single-sample NTP-style estimate with no low-RTT selection, filtering, confidence, or stable state | No | Insufficient for precise cross-device latency |
| Frame age | Android receive time through render callback | >=1 s arithmetic mean / ms | Single-clock receive-to-render measurement. Despite its name, `latestFrameAgeMs` is neither latest nor full-pipeline age | No | Rename and add latest/P50/P95/P99 |
| Estimated E2E | Mac `encode()` entry through Android render, after applying offset | >=1 s arithmetic mean / ms | Cross-clock estimate; the capture timestamp is not the SCStream callback entry | No | Comparative A/B only after stable offset and confidence reporting |
| Mac pending sends / queue | Increment before send and decrement at completion | Ping snapshot / frames | Measured snapshot; capture currently drops only when the value is greater than three | No | Export a time series and P95/P99 |
| Mac dropped frames | Pre-encode drops caused by backpressure | ~2 s interval / frames | Measured interval reset after ping; not every possible drop | No | Suitable with classified and cumulative counts |
| Android queue depth | Latest-wins one-slot state, 0 or 1 | Metrics publication snapshot / frames | Measured snapshot likely to be zero at sampling time | No | Measure distribution and occupied time |
| Android dropped frames | Latest-slot replacement/protection and MediaCodec input/oversize/error paths | >=1 s mixed interval / frames | Measured, but several causes are merged | No | Split causes before attribution |
| Input P50 / P95 | Android touch with offset-derived Mac time through Mac `CGEvent.post` | Rolling sample set; when >240, first 120 removed / ms | Cross-clock estimate of Android send to Mac event post, not touch-to-photon. P95 is sent but discarded by Android | No; P50 overlay only | Useful as a control-path estimate after P95/export wiring; never label photon latency |

Primary code evidence: `Mac/MacSender.swift:585-615,935-993,1013-1033,1146-1171`, `Mac/StreamEncodingPolicy.swift:29-49,74-87`, `Mac/VirtualDisplay.swift:48-97`, `AndroidReceiver/.../OpenDisplayServer.java:211-330,388-475`, `VideoFrameTelemetry.java:18-47`, `H264SurfaceDecoder.java:99-191`, and `MainActivity.java:525-586,680-683`.

## Reliable measurements, configuration values, and gaps

### Existing runtime measurements

Capture/encoded/sent/received/decoded/rendered FPS, actual virtual-display and Android display Hz, local actual send bitrate, average encoded frame size, encode API latency, RTT, Mac pending sends and backpressure drops, Android slot/decode drops, and receive-to-render frame age all have runtime producers.

Most are available only in an overlay, ping, or text log. They do not yet constitute a formal benchmark dataset.

### Configuration values

Requested FPS, target bitrate, codec, resolution, quality multiplier, transport, and VideoToolbox keyframe interval are requests. They must be reported separately from actual refresh, actual bitrate, rendered FPS, and observed keyframes.

### Estimates or misleading names

- `decodeLatencyMs` is estimated send-to-render latency.
- `latestFrameAgeMs` is a window average of receive-to-render latency.
- `endToEndLatencyMs` depends on a single clock-offset sample.
- Input P50/P95 covers only Android send through Mac `CGEvent.post`.

### Missing capabilities

1. Periodic structured Android-to-Mac stats. A `statsJson` helper exists, but the Android path does not call it.
2. Session/run ID, scene, unified timeline, CSV, and JSONL.
3. P50/P95/P99 for frame age, E2E, RTT, and queues.
4. Separate MediaCodec queue-to-output and output-to-render latency.
5. Persisted encoded-payload and wire bitrate with distinct scopes.
6. Classified Android drops, cumulative Mac drops, and keyframe count/size.
7. Mac CPU/memory and Android CPU/memory/thermal. Unavailable values must be `notAvailable`, never zero.
8. Structured reconnect, peer-ready, and first-frame events.

## Cross-device clock error

The current ping/pong uses an NTP-style formula, but every valid sample replaces the previous offset. It rejects only RTT values below zero or at least 2000 ms. It has no multi-sample window, high-RTT outlier rejection, median/lowest-RTT selection, drift tracking, confidence, or `estimating`/`unavailable` state. Both devices use wall clocks, so system synchronization or manual clock changes can cause discontinuities.

Until this is fixed, single-Android-clock measurements such as receive-to-render can support comparisons. E2E, send-to-render, and input latency must be labeled low-confidence estimates and must not display false precision.

## Minimum changes required for a short benchmark

1. Android sends structured stats at least once per second: receive/decode/render FPS, actual Hz, frame-age distribution, estimated E2E, RTT, offset state, queue, and classified drops.
2. Mac merges local capture/encode/send, target/actual bitrate, frame size, encode latency, queue/drops, and Android stats by session/run/scene.
3. Write both CSV and JSONL with wall timestamp, monotonic elapsed time, transport, codec, resolution, and requested settings. Missing fields use `notAvailable`.
4. Correct misleading field names, periodically reread the virtual-display mode, show actual Android Hz, and preserve input P95.
5. Debug Benchmark Mode fixes warm-up/run duration and scene; it records real samples and never synthesizes performance values.

## Prerequisites for bitrate optimization

- Fix device, commit, resolution, scale, codec, FPS, content, and thermal starting state; disable adaptation for the baseline.
- Record target bitrate, encoded-payload bitrate, and wire bitrate separately.
- Record rendered FPS, frame-age distribution, queue distribution, classified drops, CPU/memory, and thermal state together.
- Establish a baseline under current caps before stepping through Manual rates. 140–200 Mbps is Benchmark Experimental only.
- Preserve the failed sample and stop a run on thermal throttling, sustained frame-age growth, or the queue stop condition.
- Do not change bitrate caps, adaptive bitrate, or send-queue policy until this measurement loop exists.

## Verification and risks

- Android: `./gradlew --no-daemon clean test assembleDebug`; four self-tests passed, 59 tasks, exit 0.
- macOS: `xcodebuild ... OpenSidecarMac ... CODE_SIGNING_ALLOWED=NO`; exit 0.
- Website/docs: production build, 17 bilingual document pairs, and release-link checks; exit 0.
- This phase changes audit documents only, so there is no before/after performance improvement data. Inventing such values would defeat the audit.
- Existing historical overlay values cannot reconstruct the missing time series; later phases must collect new samples.

The next phase must implement Android stats return, a benchmark recorder, and corrected field semantics before any bitrate or queue policy change.

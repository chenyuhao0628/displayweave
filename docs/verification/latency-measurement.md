[English](latency-measurement.md) | [简体中文](latency-measurement.zh-CN.md)

# Latency Measurement

DisplayWeave reports latency as measured stages and explicitly labeled estimates. It does not claim photon-to-photon latency.

## Timeline

| Timestamp | Clock / current status | Meaning |
| --- | --- | --- |
| `captureTimestamp` | Mac wall clock; currently sampled at encoder entry | A captured frame enters the encode path; not yet the exact SCStream callback boundary |
| `encoderSubmitTimestamp` | Mac monotonic target | Immediately before `VTCompressionSessionEncodeFrame` |
| `encoderOutputTimestamp` | Mac monotonic target | VideoToolbox completion with encoded output |
| `socketSendTimestamp` | Mac wall clock today | Encoded payload handed to the framed socket path |
| `androidReceiveTimestamp` | Android wall clock today | Receiver accepts the complete framed payload |
| `decoderSubmitTimestamp` | Android monotonic target | Frame queued to MediaCodec |
| `decoderOutputTimestamp` | Android monotonic target | MediaCodec output becomes available |
| `renderTimestamp` | Android wall clock today | MediaCodec render callback fires; not proof of photon scanout |

“Target” means the timestamp is required to isolate that stage but is not yet exported independently. Missing timestamps produce unavailable fields, not reconstructed values.

## Metric definitions

- **Encode API latency:** Mac time immediately before VideoToolbox submission to completion. It excludes ScreenCaptureKit waiting.
- **Network transit estimate:** `androidReceive - socketSend` after applying a stable clock offset. It includes framing and transport scheduling and is unavailable while clocks are estimating.
- **MediaCodec latency:** decoder submit to decoder output on one Android monotonic clock. This is a target field; the legacy “decode latency” was actually send-to-render.
- **Render delay:** decoder output to render callback on Android. It does not include panel scanout.
- **Receive-to-render Frame Age:** Android receive to render callback on one clock. Export average, latest, P50, P95, and P99.
- **Estimated E2E:** Mac capture/encoder-entry timestamp to Android render after clock correction. Use it for matched relative comparisons, not as an absolute photon latency claim.
- **Input P50/P95:** Android control-message send estimate to Mac `CGEvent.post`; it excludes touch sampling before send and visual response after posting.

## Clock synchronization

Android sends `t1`. Mac records receive `mr` and send `ms` while retaining legacy `mt`; Android records `t2`. For each four-timestamp sample:

`RTT = (t2 - t1) - (ms - mr)`

`offset = ((mr - t1) + (ms - t2)) / 2`

The receiver keeps a bounded multi-sample window, rejects negative or over-250-ms RTT, selects the lowest-RTT half, and uses the median offset. It reports confidence as half the selected RTT spread. Fewer than three accepted samples are `estimating`; missing or rejected samples are unavailable. Cross-clock E2E and send-to-render values remain JSON `null` / CSV `notAvailable` until the estimator is stable.

Both ends still use wall timestamps for cross-device frame markers. System clock adjustment and asymmetric paths can bias the estimate. Confidence is an uncertainty signal, not a guarantee of accuracy or symmetric transport.

## Benchmark interpretation

Prefer single-clock Frame Age and rendered FPS when clock state is not stable. Once stable, compare E2E distributions only between runs with similar RTT/confidence and identical conditions. Never replace missing decode, input, CPU, or thermal data with RTT or zero. A mean without P95 is insufficient for a latency conclusion.

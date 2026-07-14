[English](android-protocol-v2-negotiation.md) | [简体中文](android-protocol-v2-negotiation.zh-CN.md)

# Android Protocol V2 Negotiation

This document describes PR 2, which adds negotiated Android session identity and receiver progress reporting on top of PR 1 Connection Generation. It does not introduce the later binary frame-header format and does not change the legacy OpenDisplay iOS receiver path.

## Purpose

PR 1 prevents callbacks from an old TCP connection from mutating a new connection. PR 2 extends that isolation inside one current connection so frames and decoder callbacks from an older stream configuration cannot be mistaken for the current stream.

```text
connection generation -> sessionEpoch -> configVersion -> frameSequence
```

## Capability negotiation

The Android hello advertises protocol version 2 and the complete capability set:

```json
{
  "protocolVersion": 2,
  "capabilities": [
    "streamConfigAck",
    "decoderReady",
    "firstFrameRendered",
    "sessionEpoch",
    "configVersion",
    "frameSequence",
    "maxFrameBytes"
  ],
  "maxFrameBytes": 8388608
}
```

The Mac enables PR 2 identity/progress behavior only when the peer is identified as Android and all six core PR 2 capabilities are present. PR 4 adds `maxFrameBytes` as a separately gated extension; see [frame-size negotiation](frame-size-negotiation.md). A missing version, partial core capability set, legacy Android hello, or iOS hello selects the unchanged legacy path.

## Identity rules

1. Every Mac transport connection that reaches `ready` receives a process-wide monotonically increasing `sessionEpoch`, including connections created by replacement `MacSender` instances.
2. A new session resets `configVersion` and `frameSequence`.
3. Every emitted `streamConfig`, including reconnect, codec fallback, reconfiguration, or finite protocol retry, increments `configVersion` and resets `frameSequence`.
4. Every encoded-frame submission increments `frameSequence`. A failed encode may leave a gap; contiguity is not required.
5. A negotiated `streamConfig` carries `protocolVersion`, `sessionEpoch`, and `configVersion`.
6. Negotiated video frames retain the existing JSON telemetry prefix and add compact `se`, `cv`, and `fs` fields. No binary V2 header is sent in this PR.
7. Android accepts a negotiated frame only when connection generation, session epoch, and config version are current and frame sequence is strictly newer.
8. Stale or duplicate frames do not enter the latest-frame slot or MediaCodec.
9. A newly accepted Android connection has no valid stream identity until it accepts a `streamConfig`.

## Receiver progress

For negotiated Android sessions, the receiver sends:

- `streamConfigAck` after validating and applying the current config identity;
- `decoderReady` only after MediaCodec starts, including actual decoder name and reported hardware/software/low-latency capability;
- `firstFrameRendered` only from the current identity's rendered-frame callback;
- `connectionState` carrying state, reason, entry time, generation, session epoch, and config version.

The state order is:

```text
SOCKET_CONNECTED -> HELLO_SENT -> HELLO_ACCEPTED
-> STREAM_CONFIG_RECEIVED -> STREAM_CONFIG_ACCEPTED
-> DECODER_CONFIGURING -> DECODER_READY
-> WAITING_FIRST_FRAME -> STREAMING
```

The Mac does not show `Connected / Streaming` for a negotiated peer until it receives the matching `firstFrameRendered`. Stale, duplicate, and out-of-order progress events are ignored.

## Decoder reconfiguration safety

A `streamConfig` emitted only because adaptive bitrate changed still receives a new config identity, but it does not destroy a compatible MediaCodec instance. Android rebinds the decoder callbacks to the new identity, republishes `decoderReady`, and waits for a frame carrying the new config version. Codec, FPS, or dimensions changes still replace the decoder. When a negotiated decoder stalls, Android marks the old decoder unavailable and requests both a fresh `streamConfig` and a keyframe; the Mac emits the config first, thereby advancing `configVersion`, before forcing the IDR. Legacy recovery keeps the existing keyframe-only request. Potentially blocking vendor `MediaCodec.stop()`/`release()` calls run on the decoder worker rather than the serialized transport-event executor, so Ack, ping, and newer configuration processing remain responsive.

## Finite timeout policy

- StreamConfig Ack: 1.5 seconds;
- Decoder Ready: 2 seconds;
- First Frame: 3 seconds.

A timeout resends `streamConfig` with a new config version and requests a keyframe. The whole handshake has a shared budget of two retries. Exhaustion may reconnect once; a second failed handshake explicitly ends the session. A proven first rendered frame resets this cross-connection budget, so the failure path cannot retry forever.

## Legacy compatibility

- The outer 4-byte big-endian length prefix is unchanged.
- Legacy iOS continues receiving the exact existing `{"cap":...,"snd":...}` telemetry prefix and Annex-B video.
- Legacy `streamConfig` has no protocol version, epoch, config version, or acknowledgement requirement.
- No binary frame header, mandatory acknowledgement, or unknown binary payload is sent to iOS.
- Existing ping/pong, touch, scroll, cursor, stats, codec failure, keyframe request, and goodbye messages remain valid.

## Modified files

- `Mac/DeviceCapabilities.swift`: complete-capability gating and legacy fallback.
- `Mac/StreamEncodingPolicy.swift`: process-wide session epochs, config/frame identity, telemetry prefix, and finite handshake policy.
- `Mac/MacSender.swift`: identity lifecycle, negotiated output, progress handling, UI phases, and timeout retries.
- `LengthPrefixedProtocol.java`: capability advertisement and PR 2 control messages.
- `ReceiverProtocolSession.java`: current identity and stale-frame filtering.
- `VideoFrameTelemetry.java`: epoch/version/sequence parsing.
- `H264SurfaceDecoder.java`, `DecoderRuntimeInfo.java`, and `DecoderReconfigurationPolicy.java`: actual decoder-ready evidence and compatible-decoder reuse.
- `OpenDisplayServer.java`: negotiation, acknowledgements, identity checks, progress publication, and non-blocking decoder replacement scheduling.
- State snapshot/coordinator/UI files and Android/Mac self-tests.

## Tests

Failure-first tests cover complete versus partial negotiation, legacy iOS fallback, process-wide epoch monotonicity, version/sequence lifecycles, stale and duplicate frame rejection, positive first-frame sequence, progress JSON, out-of-order progress rejection, two-retry exhaustion, the one-reconnect cross-connection budget, bitrate-only decoder reuse, replacement on codec/FPS/dimension changes, fresh-config recovery after a negotiated decoder reset, and byte-for-byte legacy telemetry and recovery-message preservation.

## Build result

Verification completed on 2026-07-14:

- Android `./gradlew --no-daemon clean test assembleDebug`: passed, 61 tasks and all six self-test groups.
- All 20 Mac standalone self-tests: passed.
- `xcodegen generate`: passed.
- macOS `OpenSidecarMac` Debug build with code signing disabled: passed.
- `OpenSidecariOS` Simulator Debug build with code signing disabled: passed.

## Before/after metrics

No same-condition physical A/B run has been completed, so this PR does not claim lower Frame Age or improved throughput. A short USB HEVC/120 validation on the connected OnePlus OPD2413 observed 191 ms from the first V2 `streamConfig` send to `firstFrameRendered`, and 218 ms for the post-takeover connection. These are single-run recovery observations, not comparative latency claims.

## Known risks

- Epoch values are process-local counters, not cryptographic or persistent identities.
- The existing 1 MiB legacy frame limit remains unchanged.
- Frames still use the JSON telemetry prefix; binary header V2 and allocation/NAL-scan work remain later stages.
- PR 2 only reported decoder low-latency capability. PR 5 now enables it with capability gating and same-decoder fallback; see [decoder low-latency selection](android-decoder-low-latency.md).
- Timeout values are deterministic-test candidates, not yet tuned from physical-device data.
- Simulator build proves source compatibility, not old TestFlight receiver runtime behavior.

## Pending physical validation

- Android WiFi HEVC 60/120 and ADB USB HEVC 60 negotiated handshakes;
- longer repeated reconnect, configuration-timeout, and stale-frame-injection checks;
- stale-frame rejection evidence from device logs;
- old OpenDisplay iOS receiver video, input, ping/pong, and reconnect behavior;
- same-condition before/after measurements.

## Completed short physical checks

- Captured the Android hello directly from device loopback and confirmed protocol version 2 plus all six capabilities.
- Completed ADB USB HEVC/120 state progression through Ack, Decoder Ready, First Frame, and Streaming.
- Completed repeated bitrate-only config versions without destroying MediaCodec or exhausting the handshake budget.
- Inserted a one-second competing socket: Android advanced from generation 1 to the probe's generation 2, then accepted the Mac as generation 3 and returned to V2 Streaming; the old disconnect did not overwrite the new state.

## Next step

PR 3 keyframe/drop policy and PR 4 frame-size negotiation are documented separately. PR 5 is the next implementation stage and covers MediaCodec low-latency selection and fallback. MediaCodec Async, binary frame header V2, buffer pools, UDP, and QUIC remain out of scope.

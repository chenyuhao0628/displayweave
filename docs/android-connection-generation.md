[English](android-connection-generation.md) | [简体中文](android-connection-generation.zh-CN.md)

# Android Connection Generation

This document describes the PR 1 connection-ownership model introduced after the [Android stability and latency audit](android-stability-latency-audit.md). It applies to the Android TCP listener used by both WiFi and per-device ADB-forwarded USB sessions. It does not change the legacy OpenDisplay wire format.

## Original failure mode

The previous receiver ran this sequence on one executor:

```text
accept -> blocking readLoop -> reader exits -> next accept
```

A half-open old socket could therefore prevent a new Mac connection from reaching the replacement logic. Transport callbacks had no connection identity, so a late old-reader disconnect or old-writer error could also clear the global connected state, release the decoder, and stop a newer stream.

## New ownership model

The listener now has three independent execution roles:

```text
single acceptor
    -> atomically install ConnectionContext(generation)
    -> close previous socket
    -> start an independent reader

single writer
    -> capture requested generation
    -> write only if that generation is still current

server transport-event executor
    -> serialize generation-bearing callbacks and state transitions
```

Each accepted connection owns an immutable context containing:

- monotonically increasing `generation`;
- `Socket`, buffered input, and buffered output;
- `connectedAtMs`;
- `lastPayloadAtMs`;
- a per-context write lock.

Every accepted socket enables both `TCP_NODELAY` and `SO_KEEPALIVE`. KeepAlive is only a secondary kernel signal; it does not replace the existing application ping/pong or later connection-health work.

## Generation rules

1. The acceptor remains in `accept()` while per-connection readers block independently.
2. A new accepted socket increments generation and atomically becomes current.
3. The previous socket is actively closed after replacement.
4. Connected, payload, disconnected, error, and writer work carry a generation.
5. Only `generation == currentGeneration` may:
   - deliver a payload;
   - publish connection state or UI status;
   - reset the current video queue;
   - release the current decoder;
   - stop current streaming;
   - send control/stat/input data.
6. A stale reader exit closes only its own socket and emits no current disconnect.
7. A stale writer failure is ignored after closing its own old context; it cannot fail the new generation.
8. Replacement retires the old decoder and creates a generation-bound decoder listener. Late codec callbacks from the previous decoder are ignored.
9. Queued video frames carry generation and are checked again before entering MediaCodec.
10. There is only one writer executor. A per-context lock also prevents the synchronous final `goodbye` from overlapping a normal write.

Generation is process-local transport identity. It is not a Session Epoch, Config Version, or Frame Sequence; those remain negotiated protocol work for PR 2.

## Application connection state

PR 1 adds a typed snapshot with:

```text
state
reason
enteredAtMs
generation
```

The enum reserves the complete progress vocabulary, while current legacy protocol events drive these observable transitions:

```text
DISCONNECTED
    -> SOCKET_CONNECTED (accepted current generation)
    -> HELLO_SENT
    -> STREAM_CONFIG_RECEIVED
    -> DECODER_CONFIGURING
    -> DECODER_READY
    -> WAITING_FIRST_FRAME
    -> STREAMING (first OnFrameRendered callback only)
```

`RECOVERING` is used by the existing decoder-stall recovery path. `FAILED` records a current-generation transport error before disconnect. `HELLO_ACCEPTED` and `STREAM_CONFIG_ACCEPTED` are reserved but are not claimed as implemented until PR 2 adds negotiated acknowledgement messages.

The UI no longer treats decoder configuration text as proof of streaming. `STREAMING` and the visible streaming panel are enabled only by the first rendered-frame callback from the current generation.

## Compatibility

- The 4-byte big-endian length prefix is unchanged.
- Legacy hello, ping/pong, stats, input, keyframe request, codec fallback, and Annex-B video payloads are unchanged.
- No V2 binary header, Session Epoch, Config Version, Frame Sequence, or mandatory acknowledgement is sent.
- The Mac sender and legacy OpenDisplay iOS receiver protocol are unaffected by the Android-internal callback change.
- WiFi and Android ADB USB continue to enter the same Android TCP listener.

## Modified files

- `WifiTcpReceiverTransport.java`: independent acceptor/readers, contexts, socket options, current-generation writer.
- `ReceiverTransport.java`: generation-bearing transport contract.
- `ReceiverConnectionCoordinator.java`: current-generation guard and typed transitions.
- `ReceiverConnectionState.java` / `ReceiverConnectionStateSnapshot.java`: state vocabulary and evidence.
- `OpenDisplayServer.java`: serialized transport events, generation-bound queues/decoder callbacks, first-frame streaming transition.
- `H264SurfaceDecoder.java`: explicit decoder-ready callback after MediaCodec starts.
- `MainActivity.java`: user-visible state mapping and structured generation logging.
- `ReceiverConnectionSelfTest.java` / `VideoStreamPolicySelfTest.java`: stale-callback and loopback takeover coverage.

## Tests

Automated coverage includes:

- old reader disconnect after new generation;
- old writer error rejected by the coordinator;
- two rapid connections with the first reader still blocked;
- new connection actively closes and replaces the blocked old socket;
- only the current generation emits disconnect;
- only the current generation writes and delivers payload;
- generation-bearing state/reason snapshots;
- TCP_NODELAY and SO_KEEPALIVE configuration;
- all existing Android protocol, lifecycle, stream-policy, and update self-tests.

## Build result

The following verification completed successfully on 2026-07-14:

- Android `./gradlew --no-daemon clean test assembleDebug`: 61 tasks, all six self-test groups passed, Debug APK assembled.
- Mac policy/self-test executables: 20 of 20 passed.
- `xcodegen generate`: passed.
- macOS Debug build for `OpenSidecarMac` with code signing disabled: passed.
- iOS Simulator Debug build for `OpenSidecariOS` with code signing disabled: passed.
- Website/docs `pnpm build`, `pnpm run check:docs`, and `pnpm run check:release`: passed.
- The loopback takeover test passed 20 consecutive sequential runs after the full suite. A separate attempt to start 20 JVM copies simultaneously exhausted the test host's startup window and was not treated as a product result.

These results prove build and deterministic ownership behavior only. They do not replace the pending physical-device checks below.

## Before/after metrics

No same-condition physical benchmark has been completed yet, so no Frame Age, reconnect-time, or time-to-first-frame improvement is claimed. The deterministic behavior change proven by loopback tests is that a second connection is accepted while the first connection's read remains blocked.

## Known risks

- Application payload timeout and video-health timeout policy are not implemented in PR 1.
- Session Epoch, Config Version, Frame Sequence, and acknowledgements remain absent.
- The Android inbound frame ceiling remains 1 MiB.
- Drop reasons and keyframe coalescing remain absent.
- Generation is reset when a new `OpenDisplayServer` instance is created; this is safe for in-process callback ownership but is not cross-process session identity.

## Pending physical validation

`adb devices -l` reported no attached Android device on 2026-07-14. No old OpenDisplay iOS receiver/TestFlight device was available either. Consequently, none of the following items is marked passed:

- WiFi and ADB USB HEVC 60/120 short runs;
- rapid reconnect and deliberately half-open old socket;
- USB remove/return, ADB server restart, permission revoke/restore;
- Android background/foreground and lock/unlock;
- current-generation first-frame state and reconnect timing from logs;
- old OpenDisplay iOS receiver connection and video/input compatibility.

## Next step

PR 2 capability negotiation, Session Epoch, Config Version, StreamConfig Ack, Decoder Ready, and First Frame reporting are now implemented and documented in [Android Protocol V2 Negotiation](android-protocol-v2-negotiation.md). PR 1 and PR 2 physical recovery and legacy iOS checks remain required before moving to PR 3.

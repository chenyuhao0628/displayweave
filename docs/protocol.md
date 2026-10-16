[English](protocol.md) | [简体中文](protocol.zh-CN.md)

# DisplayWeave protocol contract

Specification revision **1**, 2026-10-16. Describes the v0.3.0-preview.1 implementation after F01–F08. Revision 1 identifies this document and its fixture set; it does **not** change any on-wire version, identifier or framing. Normative behavior is implemented in the linked parsers and covered by the tests below. Hardware performance is not a protocol guarantee.

## Namespaces and compatibility

| Signal | Meaning and enablement |
| --- | --- |
| `_opensidecar._tcp`, TCP 9000 | Inherited discovery/service identity on LAN; preserved for compatibility. |
| TXT `security=tls-v1` | Secure listener hint. Discovery is not authenticated; pins and retained pairing history decide trust. |
| Mac `pv=3` | Inherited upstream namespace, independent of Android version and input extensions. |
| `protocolVersion=2` | Android identity/progress support, enabled only with the complete six-capability set below. |
| `binaryFrameHeaderV2` | Independent Android binary video header capability; never inferred from the version alone. |
| `appleVideoV1` | iOS explicit codec/FPS envelopes. Mac receiver identity already selects Apple envelopes. |
| `pencil-v1` / `pencil-v2` | Explicit basic/advanced Pencil negotiation. V2 requires authenticated TLS. |
| `mac-input-v1` | Explicit Mac receiver desktop input; authenticated TLS and both local consents required. |

Unknown optional JSON members may be ignored. Unknown control message types do not enable features. An absent/partial capability advertisement selects its existing compatibility path. Unknown binary versions/flags, invalid outer lengths and failed authentication are rejected. An implementation must not use a device label as cryptographic proof of hardware type.

## Transport and authentication

LAN uses a direct TCP connection. ADB forwarding and the owned usbmux relay carry the same stream; they do not change the application protocol. Secure mode starts TLS before any application frame. There is no STARTTLS, in-band plaintext negotiation or automatic plaintext retry. Explicit legacy modes are independently enabled on both roles; an installation ID with pairing history cannot downgrade. Pairing revocation retains history.

TLS uses platform stacks, mutual certificates and a SHA-256 pin of the complete DER leaf certificate. Transport keys are distinct from app/update-signing keys. TLS 1.2+ uses ECDHE/AEAD; TLS 1.3 is supported. Apple disables ticket/session resumption; Android uses a fresh SSLContext per connection. Current identities expire after 365 days; expiry/key loss requires explicit reset and re-pairing. See [security design](secure-transport-design.md) for persistence, threat model and recovery.

Authentication payloads also use the outer UInt32 framing described below, but have a **4 KiB** maximum and a ten-second absolute admission deadline (including trickled bytes). At most two pending admissions are accepted. No hello, video or input is admitted before authentication. New invalid candidates cannot replace an active authenticated session.

| Item | Exact payload, network byte order |
| --- | --- |
| Invitation text, at most 2 KiB | `DW1.` + canonical unpadded base64url of `DWP1` + UInt16 ID-byte-length + UTF-8 receiver ID + 32 pin bytes + 32 random token bytes. Outer whitespace may be trimmed. |
| Client auth `DWA1` | Four ASCII bytes + one flags byte + UInt16-length UTF-8 sender ID + UInt16-length UTF-8 sender name + optional 32-byte token. Flag bit 0 means token present; all other bits are invalid. |
| Server ready `DWR1` | Four ASCII bytes + UInt16-length UTF-8 receiver ID, which must match the sender's pinned intended identity. |

IDs are nonempty and at most 256 UTF-8 bytes; names may be empty and are at most 128 bytes. ASCII control characters/DEL, malformed UTF-8, truncation and trailing bytes are rejected. A pairing window lasts 120 seconds, permits one successful use and closes after five incorrect-token attempts. Tokens are memory-only and absent from discovery/logs/preferences. Trust storage holds at most 128 peer records, including revocation history. Authentication success must be persisted before it becomes usable.

## Outer framing and resource limits

Every frame is `[UInt32BE payloadByteCount][exact payload bytes]`. Zero lengths are invalid. TCP segmentation has no meaning: readers must handle partial headers/payloads and multiple coalesced frames; EOF during a frame ends that connection. Do not allocate or wait for an unchecked peer length.

| Path | Maximum accepted application payload |
| --- | --- |
| Apple receiver video channel | 16 MiB; network reads at most 256 KiB per callback. Pure JSON controls have a lower 256 KiB limit. |
| Android legacy receive | 1 MiB. |
| Android negotiated receive | Default 8 MiB, bounded by explicit `maxFrameBytes` negotiation and absolute 16 MiB ceiling. |
| Mac sender inbound control | Strictly less than 1 MiB. Desktop/Pencil action decoders further limit their message to 4 KiB. |
| Apple receiver outbound input | Admission before dispatch, at most 64 queued/in-flight writes. iOS framed batches at most 64 KiB; Mac desktop events at most 4 KiB each. Overflow closes the owning session. |
| Android outbound controls | One worker, 128 queued tasks, at most 64 KiB per control payload. |

Android receive buffers use explicit retained leases, at most 32 MiB / 32 buffers, with a 250 ms saturation wait. Capacity is not payload length. Stale callback, queue replacement, decoder completion, failure and shutdown release only their owned references. A buffer cannot be reused while any consumer owns it. See [allocation contract](android-binary-frame-header-v2.md).

## Hello, readiness and video configuration

After authentication the receiver sends JSON `hello` with `id`, `device`, `pixelsWide`, `pixelsHigh`, `scale`, plus capabilities and codec/display envelopes where supported. The sender must match `hello.id` against authenticated/pinned identity before capture/control is considered ready. TCP connect alone is not application readiness.

Logical desktop geometry and encoded resolution are distinct. Mac `panel` can carry logical points and 1×/2× scale. Each `videoCaps` entry combines codec, width/height, frame-rate and optional pixels-per-second limits; multiple same-codec entries are alternatives. Sender selection must fit a complete envelope and retain a viable H.264 fallback. Source Apple refresh selection is bounded by screen, codec and throughput limits, up to 120fps; it is a request, not measured rendering.

`streamConfig` declares `codec`, `width`, `height`, `fps` (Apple also accepts inherited `framesPerSecond`) and applicable bitrate/identity/frame-size fields. Apple dimensions must be positive even values within advertised bounds, at most 8192; FPS at most 120 and aggregate pixels per second at most `4096 × 2304 × 60`. HEVC failure emits `codecFailure`; sender falls back to H.264. Apple receivers allow three seconds for fallback and do not re-upgrade HEVC on the failed connection.

Android core V2 requires `protocolVersion >= 2`, Android identity and **all six** of `streamConfigAck`, `decoderReady`, `firstFrameRendered`, `sessionEpoch`, `configVersion`, `frameSequence`. `maxFrameBytes` and `binaryFrameHeaderV2` remain independently gated.

```text
TLS/auth -> hello -> streamConfig -> matching streamConfigAck
         -> matching decoderReady -> matching firstFrameRendered -> streaming
```

A process-wide positive `sessionEpoch` advances per ready transport; every config advances positive `configVersion` and resets the frame sequence. Every submitted frame advances positive `frameSequence`; gaps are allowed. A socket generation additionally owns callbacks locally. Stale generation/epoch/config or non-increasing frame sequence cannot mutate decoder queues or readiness. These numbers are not authentication credentials.

Android progress deadlines are 1.5 seconds for Ack, 2 seconds for decoder readiness and 3 seconds for first frame. The handshake shares two retries, each with a fresh config and keyframe request; exhaustion permits one reconnect, then ends explicitly. A proven rendered frame resets that cross-connection budget. A compatible bitrate-only reconfiguration may rebind an existing decoder; codec/FPS/dimension changes replace it. Detailed state rules: [Android negotiation](android-protocol-v2-negotiation.md).

## Video payload formats

Legacy Apple and Android without the binary capability retain `{"cap":1000,"snd":1010}` followed **immediately** by Annex-B NAL bytes. There is no separator or outer format change. Core Android V2 without binary adds compact `se`, `cv`, `fs` fields to that JSON prefix. Timestamps are Unix milliseconds. Pure JSON control has no Annex-B payload. H.264 uses SPS/PPS and HEVC uses VPS/SPS/PPS; receivers bound NAL count, parameter sizes and frame dimensions before rendering.

Negotiated Android binary payload is exactly this header followed by Annex-B. Outer length includes header and payload:

| Offset | Bytes | Field |
| ---: | ---: | --- |
| 0 | 4 | ASCII `DWV2` |
| 4 | 1 | Version 2 |
| 5 | 1 | Flags: keyframe `0x01`, codec config `0x02`, HEVC `0x04`, H.264 `0x08` |
| 6 | 2 | Header length 52 |
| 8 | 8 | Session epoch |
| 16 | 8 | Config version |
| 24 | 8 | Frame sequence |
| 32 | 8 | Capture timestamp |
| 40 | 8 | Send timestamp |
| 48 | 4 | Annex-B payload byte count |
| 52 | variable | Exact Annex-B payload |

All integers are big-endian. Identity values are 1…Int64.max and timestamps 0…Int64.max. Exactly one codec flag is required; unknown bits are invalid. Payload must be nonempty, at most `16 MiB − 52`, and header length plus payload length must equal the outer payload length. A lower negotiated limit still applies. Header codec must match the accepted stream configuration. DWV2 is never sent to Apple receivers.

## Control and lifecycle

Common JSON controls include `ping`/`pong`, `stats`, `kf`, `codecFailure`, `cursor`/`cursorImg`, touch/scroll, and receiver closing/sleeping/goodbye messages. Ping timestamps/round trips estimate clock offset and liveness; they do not prove one-way display latency. Cursor images are separately bounded and validated. `kf` requests a keyframe; Android V2 recovery may include `streamConfigRequired` so a fresh configuration precedes the IDR.

Mac sender liveness checks run every two seconds and detect more than five seconds of silence; recovery is bounded. iOS also detects five seconds of silence, Mac receiver eight seconds. Protocol admission has its own absolute deadline. A stop, role change, background/sleep or failed connection invalidates the owning generation, cancels input and closes only its resources. Sender and receiver roles on one Mac remain exclusive. Reconnect must repeat authentication, hello and applicable configuration/readiness. See [Mac handover](mac-lan-handover.md) for same-ID interface transitions; Android ADB recovery remains separate.

## Input extensions

Coordinates are normalized top-left video space. New desktop input uses aspect-fit mapping and ignores black bars; drag release clamps to the picture. Physical macOS key codes use the sender's keyboard layout/input method. Input never implies clipboard/file transfer or global keyboard capture.

**Touch and Pencil V1:** inherited `touch` phases `began`/`moved`/`ended`/`cancelled`, coordinates `x/y`, and `scroll.dx/dy` remain compatible. `pencil-v1` requires explicit hello and `inputConfig` agreement. A `pencil` message has `phase` (`down/move/up/cancel/hover`), x/y/pressure in [0,1], azimuth in [−2π,2π] and altitude in [0,π/2], all finite numbers, not JSON booleans. Non-contact phases force zero pressure. A stroke fixes legacy-touch versus native mode when it begins. `proximity` carries entering and normalized position.

**Pencil V2:** additionally negotiate `pencil-v2` over authenticated TLS. `pencil2` retains V1 fields and requires `roll` in [−2π,2π] radians and `tool` of `pen` or `eraser`. Roll becomes normalized degrees for the Mac tablet event. Tool changes release the previous stroke/proximity. UIKit double tap and completed squeeze map locally to tool selection or named actions. See [advanced Pencil](pencil-advanced.md).

Pencil shortcuts additionally require default-off sender consent and Accessibility. `inputConfig.pencilActionSession` grants a fresh UUID; `pencilActionStatus` explains denial/readiness. Receiver sends `pencilAction` with `inputSession`, strictly increasing integer `sequence` (1…2^53−1) and `action` of `undo`, `redo`, `shortcut1`, or `shortcut2`. Mac owns key/modifier mappings; remote arbitrary keys are not accepted on this channel. At most five actions in a rolling second; rate-limited sequence values are consumed. Connection/target/permission changes revoke grants. Every shortcut cancels tablet input and sends a balanced chord.

**Mac desktop input:** authenticated Mac hello advertises `mac-input-v1`. The sender must opt in and have Accessibility; the receiver must opt in separately. `inputConfig` grants `inputSession` UUID, capability and `inputStatus`. `desktopInput` includes that UUID, strictly increasing integer `sequence` (1…2^53−1), `kind`, and `modifiers`. Modifier bits are Shift 1, Control 2, Option 4, Command 8 and Caps Lock 16; other bits are rejected.

| Kind | Required extra fields |
| --- | --- |
| `move` | x/y in [0,1] |
| `buttonDown`, `buttonUp` | x/y, button 0/1/2 (left/right/middle), clicks 1…3 |
| `scroll` | x/y, dx/dy in [−4096,4096] |
| `keyDown`, `keyUp` | keyCode 0…127 excluding modifier key codes 54…63; optional Boolean `repeat` |
| `modifiers` | Only common fields; modifiers represent the aggregate state |
| `releaseAll` | Only common fields; releases owned keys/buttons/modifiers |

At most 16 regular keys and three buttons can be held. Duplicate/stale grant sequences are ignored. Invalid shapes cancel the active grant/state. Input captures only the focused receiving video view; focus loss, disable, close, role changes and disconnect release it. Control–Option–Escape disables forwarding locally. Consent/permission is checked per event and within two seconds during idle. OS permission withdrawal can prevent synthetic release delivery, but owned state is always cleared. See [Mac input](mac-receiver-input.md).

## Shared fixtures and verification

[`wire-contract-v1.properties`](../tools/fixtures/wire-contract-v1.properties) contains public synthetic, hexadecimal vectors for outer framing, legacy telemetry, H.264/HEVC DWV2, invalid versions/flags/identity/lengths, and Apple input. Swift `WireContractSelfTest` and Java `WireContractSelfTest` consume the same bytes and actual production parsers/encoders. Swift exercises every split boundary and coalescing; Java exercises one-byte reads, coalescing and truncated EOF. Apple-only input semantics are validated by Swift; Java validates their framing as opaque control bytes.

[`secure-pairing-v1.properties`](../tools/fixtures/secure-pairing-v1.properties) is the existing shared auth/invitation/ready corpus. Real Apple↔Java TLS and production receiver runtime suites supplement the byte fixtures. Golden vectors do not replace permission, role/lifecycle, native key-storage or hardware tests.

```sh
./tools/run-swift-self-tests.sh
(cd AndroidReceiver && ./gradlew --no-daemon test assembleDebug lintDebug)
python3 tools/test-tls-interop.py
python3 tools/test-apple-keychain.py --ios-simulator
python3 tools/test-secure-ios-receiver.py
python3 tools/test-secure-android-receiver.py
pnpm run check:docs
```

The normative source contracts are `Shared/ReceiverFrameDecoder.swift`, `Shared/SecurePairingProtocol.swift`, `Mac/DeviceCapabilities.swift`, `Mac/StreamEncodingPolicy.swift`, `Mac/BinaryFrameHeaderV2.swift`, `Shared/AppleVideoPolicy.swift`, `Shared/PencilProtocol.swift`, `Shared/PencilActions.swift`, `Shared/DesktopInputProtocol.swift`, and Android `protocol/LengthPrefixedProtocol.java`, `protocol/BinaryFrameHeaderV2.java`, `SecurePairingProtocol.java`, and `ReceiverProtocolSession.java`.

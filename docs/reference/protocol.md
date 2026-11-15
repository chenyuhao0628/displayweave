[English](protocol.md) | [简体中文](protocol.zh-CN.md)

# DisplayWeave protocol contract

Specification revision **3**, 2026-11-15. Revision 1 (2026-10-16) documented the `v0.3.0`–`v0.3.5` framed TCP/mTLS contract after F01–F08. Revision 2 added the source-branch authenticated UDP media, cursor and audio plane (`udpMediaV1`, `udpCursorV1`, `udpAudioV1`), hardware-gated 5K HEVC (`hevc5kV1`), Apple Display P3 signaling (`displayP3`), physical `panel` millimeter geometry (`millimetersWide`, `millimetersHigh`), and cross-platform iPadOS/Android stylus and desktop input over `pencil-v1`/`pencil-v2` and `mac-input-v1`. Revision 3 adds zero-ADB Android USB Open Accessory 2.0 (`AOA 2.0`) transport with deterministic ADB-first arbitration and loopback mTLS (`DWA1`/`DWR1`), authenticated TCP audio (`tcpAudioV1`), `48 kHz` Opus audio packets (`audioOpusV1`, `UDPMediaAudioPayload.formatFlags = 1`) with RFC 7845 `OpusHead` decoder configuration, clock-offset-invariant A/V lip-sync (`120 ms` ring cap, `15…90 ms` dynamic playout watermark, `target + 25 ms` drift trim), end-to-end `displayP3` across `CGVirtualDisplayDescriptor` CIE 1931 P3 primaries and wide-gamut Android receivers (`streamConfig.colorSpace`), and iPadOS Split View / Stage Manager live window clamping (`320…16384` even pixels, `150 ms` debounce). Post-`v0.3.5` Revision 2 and Revision 3 capabilities are **implemented on the source branch and not yet included in the published `v0.3.5` release downloads**; absent capability tokens preserve full wire compatibility with `v0.3.5` and earlier peers. Normative behavior is implemented in the linked parsers and covered by the tests below. Hardware performance is not a protocol guarantee.

## Namespaces and compatibility

| Signal | Meaning and enablement |
| --- | --- |
| `_opensidecar._tcp`, TCP 9000 | Inherited discovery/service identity on LAN; preserved for compatibility. |
| TXT `security=tls-v1` | Secure listener hint. Discovery is not authenticated; pins and retained pairing history decide trust. |
| Mac `pv=3` | Inherited upstream namespace, independent of Android version and input extensions. |
| `protocolVersion=2` | Android identity/progress support, enabled only with the complete six-capability set below. |
| `binaryFrameHeaderV2` | Independent Android binary video header capability over TCP; never inferred from the version alone. |
| `appleVideoV1` | iOS explicit codec/FPS envelopes. Mac receiver identity already selects Apple envelopes. |
| `hevc5kV1` | Source-branch Mac hardware-HEVC receiver capability enabling HEVC envelopes up to `5120 × 2880 @ 60` (`2880 × 5120 @ 60` portrait); H.264 fallback remains capped at `4096 × 2304`. |
| `displayP3` | Source-branch wide-gamut Display P3 color-space signaling across `CGVirtualDisplayDescriptor` CIE 1931 P3 primaries, Apple streams (`P3_D65` / `sRGB` / `ITU_R_709_2`), and wide-gamut Android receivers (`streamConfig.colorSpace` `"displayP3"` / `"srgb"`). |
| `udpMediaV1` | Source-branch authenticated AES-128-GCM UDP video, parity FEC, NACK and delay-gradient feedback plane negotiated over mTLS TCP (`udpMediaConfig` / `udpMediaReady`) with automatic TCP fallback. |
| `udpCursorV1` | Source-branch `125 Hz` normalized cursor coordinate datagrams (`packetType = 5`) over an active `udpMediaV1` session; cursor PNG bitmaps stay on TCP. |
| `udpAudioV1` | Source-branch opt-in `48 kHz` S16LE PCM (`formatFlags = 0`) or negotiated Opus (`formatFlags = 1`) system audio datagrams (`packetType = 6`) over an active `udpMediaV1` session when enabled on the sender. |
| `tcpAudioV1` | Source-branch opt-in system audio over authenticated mTLS TCP (`{"type":"audioFrame","payload":"<base64>"}`, `<= 4,096` UTF-8 bytes) for wired USB (`usbmux`, `adb forward`, `AOA 2.0`) and UDP-blocked networks, sharing `UDPMediaAudioPayload` and monotonic `audioSeq` across UDP↔TCP handovers. |
| `audioOpusV1` | Source-branch `48 kHz` Opus system audio encoding (`UDPMediaAudioPayload.formatFlags = 1`, `20 ms` / `960` stereo frames @ `128 kbps` with automatic `5 ms` S16LE fallback) over `udpAudioV1` or `tcpAudioV1`. |
| `pencil-v1` / `pencil-v2` | Explicit basic/advanced stylus negotiation (iPadOS Apple Pencil and source-branch Android `TOOL_TYPE_STYLUS` / `TOOL_TYPE_ERASER`). V2 requires authenticated TLS. |
| `mac-input-v1` | Explicit consented desktop keyboard/pointer input (Mac receiver, plus source-branch iPadOS/iOS and Android external hardware keyboards/mice/trackpads); authenticated TLS and both local consents required. |

Unknown optional JSON members may be ignored. Unknown control message types do not enable features. An absent/partial capability advertisement selects its existing compatibility path. Unknown binary versions/flags, invalid outer lengths and failed authentication are rejected. An implementation must not use a device label as cryptographic proof of hardware type.

## Transport and authentication

LAN uses a direct TCP connection (on the source branch, Mac sender LAN/Bonjour TCP connections set `NWParameters.preferNoProxies = true` via `LANProxyBypassPolicy` while preserving loopback `127.0.0.1` / `::1` / `localhost` ADB, AOA and usbmux tunnels). ADB forwarding, the owned usbmux relay, and source-branch Android USB Open Accessory 2.0 (`AOA 2.0`) carry the same `[UInt32BE][payload]` byte stream; they do not change the application protocol. On the source branch, `AccessoryDeviceWatcher` matches only `.adb` (`0xFF/0x42/0x01`) and `.mtp` USB interfaces (ignoring docks, cameras, MIDI devices and Apple `0x05AC`), probes `GET_PROTOCOL` (`51`) at most once per `IOUSBHostDevice` registry entry when no online `adb` `device` row claims that serial (`AndroidWiredArbitrationPolicy` prefers online `adb` rows and maps `0xE00002C5` `kIOReturnExclusiveAccess` to `.busy` rather than silent fallback), sends AOA identification strings (`52`, `"OpenDisplay"` / `"OpenDisplay Receiver"`) and `START` (`53`) to re-enumerate as `0x18D1:0x2D00`/`0x2D01`, transfers over `16 KiB` (`16,384 B`) bulk IN/OUT URBs (appending a bulk OUT ZLP when `byteCount % maxPacketSize == 0 && byteCount % 16384 != 0` and tolerating up to `64` consecutive zero-length bulk IN reads), and bridges via `127.0.0.1` loopback into `UsbmuxTLSRelay` + `AppleTLS` + `AppleSecureAdmission` (`DWA1`/`DWR1`) and Android `LoopbackAccessoryBridge` + `SecureSocketAdmission` mutual TLS by default (allowing a `25 s` pre-data hello deadline on AOA so the user can accept Android's USB accessory dialog, `20 s` disconnect grace, and session-scoped fallback suppression when dismissed). Secure mode starts TLS before any application frame. There is no STARTTLS, in-band plaintext negotiation or automatic plaintext retry. Explicit legacy modes are independently enabled on both roles; an installation ID with pairing history cannot downgrade. Pairing revocation retains history.

TLS uses platform stacks, mutual certificates and a SHA-256 pin of the complete DER leaf certificate. Transport keys are distinct from app/update-signing keys. TLS 1.2+ uses ECDHE/AEAD; TLS 1.3 is supported. Apple disables ticket/session resumption; Android uses a fresh SSLContext per connection. Current identities expire after 365 days; expiry/key loss requires explicit reset and re-pairing. See [security design](secure-transport-design.md) for persistence, threat model and recovery.

Authentication payloads also use the outer UInt32 framing described below, but have a **4 KiB** maximum and a ten-second absolute admission deadline (including trickled bytes). At most two pending admissions are accepted. No hello, video or input is admitted before authentication. New invalid candidates cannot replace an active authenticated session.

| Item | Exact payload, network byte order |
| --- | --- |
| Invitation text, at most 2 KiB | `DW1.` + canonical unpadded base64url of `DWP1` + UInt16 ID-byte-length + UTF-8 receiver ID + 32 pin bytes + 32 random token bytes. Outer whitespace may be trimmed. |
| Client auth `DWA1` | Four ASCII bytes + one flags byte + UInt16-length UTF-8 sender ID + UInt16-length UTF-8 sender name + optional 32-byte token. Flag bit 0 means token present; all other bits are invalid. |
| Server ready `DWR1` | Four ASCII bytes + UInt16-length UTF-8 receiver ID, which must match the sender's pinned intended identity. |

IDs are nonempty and at most 256 UTF-8 bytes; names may be empty and are at most 128 bytes. ASCII control characters/DEL, malformed UTF-8, truncation and trailing bytes are rejected. A pairing window lasts 120 seconds, permits one successful use and closes after five incorrect-token attempts. Tokens are memory-only and absent from discovery/logs/preferences. Trust storage holds at most 128 peer records, including revocation history. Authentication success must be persisted before it becomes usable.

## Outer framing and resource limits

Every TCP frame is `[UInt32BE payloadByteCount][exact payload bytes]`. Zero lengths are invalid. TCP segmentation has no meaning: readers must handle partial headers/payloads and multiple coalesced frames; EOF during a frame ends that connection. Do not allocate or wait for an unchecked peer length.

| Path | Maximum accepted application payload |
| --- | --- |
| Apple receiver TCP video channel | 16 MiB; network reads at most 256 KiB per callback. Pure JSON controls have a lower 256 KiB limit. |
| Android legacy TCP receive | 1 MiB. |
| Android negotiated TCP receive | Default 8 MiB, bounded by explicit `maxFrameBytes` negotiation and absolute 16 MiB ceiling. |
| `udpMediaV1` datagram | 32…1232 wire bytes (`16 B` AAD header + `0…1200 B` ciphertext + `16 B` AES-128-GCM tag); reassembled `videoData` frame payload at most 4 MiB across at most 2048 fragments. |
| `tcpAudioV1` `audioFrame` control | At most 4 KiB (`4,096` UTF-8 bytes; `base64` body `<= 2,048` ASCII chars wrapping `16 + 1…1152 B` `UDPMediaAudioPayload`). Sender drops immediately without queuing when `pendingSends > 2` or `pendingTCPAudioSends >= 2`. |
| Mac sender inbound control | Strictly less than 1 MiB. Desktop/Pencil action decoders further limit their message to 4 KiB. |
| Apple receiver outbound input | Admission before dispatch, at most 64 queued/in-flight writes. iOS framed batches at most 64 KiB; Mac/iPadOS desktop events at most 4 KiB each. Overflow closes the owning session. |
| Android outbound controls | One worker, 128 queued tasks, at most 64 KiB per control payload. |

Android receive buffers use explicit retained leases, at most 32 MiB / 32 buffers, with a 250 ms saturation wait. Capacity is not payload length. Stale callback, queue replacement, decoder completion, failure and shutdown release only their owned references. A buffer cannot be reused while any consumer owns it. See [allocation contract](android-binary-frame-header-v2.md).

## Hello, readiness and video configuration

After authentication the receiver sends JSON `hello` with `id`, `device`, `pixelsWide`, `pixelsHigh`, `scale`, plus capabilities and codec/display envelopes where supported. The sender must match `hello.id` against authenticated/pinned identity before capture/control is considered ready. TCP connect alone is not application readiness.

Logical desktop geometry, physical panel size and encoded resolution are distinct:

- `hello.panel` may carry logical `pointsWide`/`pointsHigh`, `pixelsWide`/`pixelsHigh`, `scale`, and optional physical `millimetersWide`/`millimetersHigh`.
- On the source branch, Mac receivers populate `millimetersWide`/`millimetersHigh` from `CGDisplayScreenSize` only when finite within `50…2000 mm` and not matching a synthetic 72-DPI fallback (`|bounds * 25.4 / 72.0 - raw| <= 1.5 mm` on both axes), while the sender accepts incoming `hello.panel` millimeters within `10…2000 mm`. iOS/iPadOS receivers report `50…2000 mm` for known device models alongside live Split View / Stage Manager window `pointsWide`/`pointsHigh`/`pixelsWide`/`pixelsHigh` (`ReceiverWindowGeometryPolicy` clamps window pixels to even `320…16384`, emits a `150 ms` debounced `hello` update when the active window settles so the sender updates virtual-display geometry and capture configuration without reconnecting, and accepts transient rotated `(width, height) == (cfgHeight, cfgWidth)` frames before rebuilding the decoder). Android receivers report `DisplayMetrics` `xdpi`/`ydpi`-derived millimeters when calibrated (`50…1000` DPI and `10…2000 mm`), accepted on `hello.panel` with or without full point geometry.
- Because macOS 26.1+ rejects `CGVirtualDisplayDescriptor.sizeInMillimeters` below ~`200 cm²` (`20,000 mm²`), the sender defaults mobile virtual displays without reported millimeters to `208 × 96 mm` (`96 × 208 mm` portrait) and proportionally scales any smaller reported `millimetersWide`/`millimetersHigh` up to `>= 20,000 mm²` while clamping edges to `<= 2,000 mm`.

Each `videoCaps` entry combines codec, width/height, frame-rate and optional pixels-per-second limits; multiple same-codec entries are alternatives. Sender selection must fit a complete envelope and retain a viable H.264 fallback. Source Apple refresh selection is bounded by screen, codec and throughput limits, up to 120fps; it is a request, not measured rendering.

`streamConfig` declares `codec`, `width`, `height`, `fps` (Apple also accepts inherited `framesPerSecond`) and applicable bitrate/identity/frame-size/color-space fields; when `udpMediaV1` is active for an Apple receiver, `streamConfig` also includes positive `configVersion` so UDP `videoData` frames bind to the matching configuration. Apple dimensions must be positive even values within advertised bounds, at most 8192; FPS is at most 120. Published `v0.3.5` downloads enforce a default aggregate pixel budget of `4096 × 2304 × 60` (with an opt-in iPad native-panel offer raising only its own rectangle's budget). On the source branch, hardware-HEVC Mac receivers advertising `hevc5kV1` add `5120 × 2880 @ 60` and `2880 × 5120 @ 60` (`maxPixelsPerSecond = 5120 × 2880 × 60`) HEVC envelopes alongside `4096 × 2304`; H.264 remains strictly capped at `4096 × 2304`, and `codecFailure` clamps 5K stream dimensions back to `<= 4096 × 2304` before rebuilding H.264. Apple receivers allow three seconds for fallback and do not re-upgrade HEVC on the failed connection. On the source branch, `VirtualDisplayColorPolicy` configures `CGVirtualDisplayDescriptor` with CIE 1931 Display P3 primaries (`(0.680, 0.320)`, `(0.265, 0.690)`, `(0.150, 0.060)`, D65 `(0.3127, 0.3290)`); when both peers advertise `displayP3`, Apple streams tag Display P3 color primaries/transfer/matrix (`P3_D65` / `sRGB` / `ITU_R_709_2`), and wide-gamut Android receivers (`Display.isWideColorGamut()`) receive `streamConfig.colorSpace` (`"displayP3"` or `"srgb"`), toggle `Window.setColorMode(COLOR_MODE_WIDE_COLOR_GAMUT)` vs `COLOR_MODE_DEFAULT`, and apply `MediaFormat` `COLOR_STANDARD_DISPLAY_P3` (`10`) with safe fallback to default color metadata if a vendor decoder rejects wide-gamut keys. See the [Apple video guide](../guides/apple-video.md).

Android core V2 requires `protocolVersion >= 2`, Android identity and **all six** of `streamConfigAck`, `decoderReady`, `firstFrameRendered`, `sessionEpoch`, `configVersion`, `frameSequence`. `maxFrameBytes` and `binaryFrameHeaderV2` remain independently gated.

```text
TLS/auth -> hello -> streamConfig -> matching streamConfigAck
         -> matching decoderReady -> matching firstFrameRendered -> streaming
```

A process-wide positive `sessionEpoch` advances per ready transport; every config advances positive `configVersion` and resets the frame sequence. Every submitted frame advances positive `frameSequence`; gaps are allowed. A socket generation additionally owns callbacks locally. Stale generation/epoch/config or non-increasing frame sequence cannot mutate decoder queues or readiness. These numbers are not authentication credentials.

Android progress deadlines are 1.5 seconds for Ack, 2 seconds for decoder readiness and 3 seconds for first frame. The handshake shares two retries, each with a fresh config and keyframe request; exhaustion permits one reconnect, then ends explicitly. A proven rendered frame resets that cross-connection budget. A compatible bitrate-only reconfiguration may rebind an existing decoder; codec/FPS/dimension changes replace it. Detailed state rules: [Android negotiation](android-protocol-v2-negotiation.md).

## TCP video payload formats

Legacy Apple and Android without the binary capability retain `{"cap":1000,"snd":1010}` followed **immediately** by Annex-B NAL bytes. There is no separator or outer format change. Core Android V2 without binary adds compact `se`, `cv`, `fs` fields to that JSON prefix. Timestamps are Unix milliseconds. Pure JSON control has no Annex-B payload. H.264 uses SPS/PPS and HEVC uses VPS/SPS/PPS; receivers bound NAL count, parameter sizes and frame dimensions before rendering.

Negotiated Android TCP binary payload is exactly this header followed by Annex-B. Outer length includes header and payload:

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

## Authenticated `udpMediaV1` media, cursor and audio plane

On the source branch, an authenticated mTLS TCP session whose receiver `hello.capabilities` includes `udpMediaV1` may negotiate an ephemeral session-scoped UDP media plane alongside the existing TCP control channel. Plaintext legacy connections never enable UDP media.

### Control handshake and TCP fallback

After sending `streamConfig` (and whenever `sessionEpoch` advances), the sender binds a local UDP socket, generates a fresh 32-byte random `rootSecret` (`SystemRandomNumberGenerator`), and sends `udpMediaConfig` over mTLS TCP:

```json
{"type":"udpMediaConfig","version":1,"sessionEpoch":1,"udpPort":51234,"rootSecret":"<base64 32 bytes>","maxPayloadBytes":1200}
```

`version` must be `1`, `sessionEpoch >= 1`, `udpPort` in `1…65535`, `rootSecret` exact 32-byte base64, and `maxPayloadBytes` clamped to `512…1200`. Receivers validate the complete control payload before mutating active media state and enforce monotonic `sessionEpoch` ordering:

- `sessionEpoch < lastAcceptedEpoch`: ignored without tearing down an active UDP or audio session.
- `sessionEpoch == lastAcceptedEpoch` with an active UDP session: preserves the existing UDP and audio session and re-emits `udpMediaReady` with the bound local `udpPort`.
- `sessionEpoch > lastAcceptedEpoch` (or no active UDP session): replaces any prior UDP session, binds an ephemeral local UDP socket, replies over mTLS TCP with `{"type":"udpMediaReady","version":1,"sessionEpoch":1,"udpPort":54321}`, and transmits up to **6** authenticated `probe` datagrams (`packetType = 4`, payload `"DWV1-RCV-PROBE"`) spaced by **150 ms**.

The sender verifies that incoming UDP datagrams originate from the peer IP authenticated on the mTLS TCP socket, responds/probes with `"DWV1-PROBE"` (`probeAck` flag `0x04`), and cuts video/cursor/audio over to UDP only after authenticated bidirectional reachability succeeds. While UDP media is ready, TCP `AdaptiveBitrateController` adjustments are suspended in favor of receiver delay-gradient feedback (`UDPDelayGradientBWE`). If UDP feedback goes silent for more than **2.5 seconds** (firewall block, NAT rebind or interface change), the sender seamlessly falls back to framed TCP, synchronizes `AdaptiveBitrateController` to the latest BWE bitrate (`syncCurrentBitrate`), and forces an immediate keyframe.

### HKDF-SHA256 key derivation, ROC and AES-128-GCM nonces

Keys and base salts are derived deterministically per `sessionEpoch` using RFC 5869 HKDF-SHA256:

- `hkdfSalt`: ASCII `"DisplayWeave-UDPMediaV1-Salt-2026"`
- `PRK = HMAC-SHA256(key: hkdfSalt, data: rootSecret)`
- `s2rInfo`: ASCII `"displayweave-udp-v1|s2r|<sessionEpoch>"` (`direction = 0`, sender to receiver)
- `r2sInfo`: ASCII `"displayweave-udp-v1|r2s|<sessionEpoch>"` (`direction = 1`, receiver to sender)
- `OKM = HKDF-Expand-SHA256(PRK, info, 28)` → bytes `0…15` = 16-byte AES-128 key, bytes `16…27` = 12-byte directional salt.

Each direction maintains a strictly increasing 64-bit packet sequence (`extendedSeq >= 1`) and writes `UInt16(extendedSeq & 0xFFFF)` into wire `packetSeq`. Before decrypting, the receiver checks `epochTag == UInt8(sessionEpoch & 0xFF)`, reconstructs the closest 64-bit `extendedSeq` via stateless rollover counter (ROC) estimation around `highestAuthenticatedSeq` (`delta = Int64(packetSeq) - Int64(highestAuthenticatedSeq & 0xFFFF)` in `−32768…32767`, adjusting across `0x10000` wrap boundaries), and checks a **1024-packet** sliding `UDPAntiReplayWindow`. The 12-byte AES-128-GCM nonce is formed by copying the 12-byte directional salt and XORing big-endian `directionalSeq = ((UInt64(direction & 0x01) << 63) | (extendedSeq & 0x7FFF_FFFF_FFFF_FFFF))` into nonce bytes `4…11`. Anti-replay state commits **only** after AES-128-GCM verification of `[16-byte AAD header][ciphertext][16-byte tag]` succeeds; invalid or replayed datagrams are dropped without mutating state.

### 16-byte `udpMediaV1` AAD header

Every UDP datagram begins with this 16-byte big-endian plaintext header authenticated as AES-128-GCM AAD, followed by `0…1200` bytes of ciphertext and a 16-byte GCM authentication tag (`32…1232` wire bytes):

| Offset | Bytes | Field |
| ---: | ---: | --- |
| 0 | 1 | `((version & 0x03) << 6) \| ((packetType & 0x07) << 3) \| (flags & 0x07)` (`version = 1`) |
| 1 | 1 | `epochTag`: `UInt8(sessionEpoch & 0xFF)` |
| 2 | 2 | `packetSeq`: low 16 bits of directional 64-bit `extendedSeq` |
| 4 | 4 | `sendTimeUs`: monotonic microseconds modulo `2^32` |
| 8 | 4 | `frameId`: modular `UInt32` identifier (`Int32(bitPattern: a &- b) > 0`) |
| 12 | 2 | `fragIndex`: fragment index (`videoData`), packed FEC descriptor (`videoParity`), or `0` (`cursor`/`audio`) |
| 14 | 2 | `fragCount`: total fragments `1…2048` (`videoData`), packed FEC descriptor (`videoParity`), or `1` (`cursor`/`audio`) |

`flags` bit `0` (`0x01`) is `keyframe`, bit `1` (`0x02`) is `endOfFrame`, and bit `2` (`0x04`) is `retransmit` (on `videoData`) or `probeAck` (on `probe`). `packetType` `7` and `version != 1` are rejected.

### `udpMediaV1` decrypted payloads (`packetType` `0…6`)

| `packetType` | Direction | Exact plaintext payload (big-endian integers) |
| ---: | --- | --- |
| `0` (`videoData`) | `s2r` | Fragment `fragIndex < fragCount` (`1 <= fragCount <= 2048`). Reassembled frame payload (`<= 4 MiB`) is `[0…7] captureTimestampMs: Int64` + `[8…15] configVersion: Int64` + exact Annex-B NAL bytes. |
| `1` (`videoParity`) | `s2r` | Systematic GF(256) (`0x11d`) Cauchy/XOR parity shard across up to `16` blocks × `1…64` data shards and `1…15` parity shards/block. Row `0` uses all-`1` XOR; rows `1…14` use `inv(UInt8(p) ^ UInt8(16 + j))`. Header `fragIndex = ((blockIndex & 0x0F) << 12) \| ((blockDataCount & 0xFF) << 4) \| (parityIndexInBlock & 0x0F)` and `fragCount = ((lastDataShardLength & 0x0FFF) << 4) \| (blockParityCount & 0x0F)` (`lastDataShardLength` in `1…1200`). |
| `2` (`nack`) | `r2s` | **20 bytes:** `[0…3] frameId: UInt32`, `[4…5] baseFragIndex: UInt16`, `[6…7] missingCount: UInt16`, `[8…15] missingBitmap: UInt64` (bit `k` = fragment `baseFragIndex + k`), `[16…19] rttEstimateUs: UInt32`. |
| `3` (`feedback`) | `r2s` | **28 bytes:** `[0…7] highestSeq: UInt64`, `[8…11] receivedCount: UInt32`, `[12…15] lostCount: UInt32`, `[16…19] arrivalGradientUs: Int32`, `[20…21] decodeQueueMs: UInt16`, `[22…23] renderFps: UInt16`, `[24…27] echoSendTimeUs: UInt32`. |
| `4` (`probe`) | `s2r` / `r2s` | ASCII `"DWV1-RCV-PROBE"` (receiver probe) or `"DWV1-PROBE"` (sender probe / `probeAck`). |
| `5` (`cursor`) | `s2r` | **17 bytes** (`udpCursorV1`, requires `fragIndex == 0 && fragCount == 1`): `[0…7] sequence: UInt64`, `[8…11] normalizedX: Float32` IEEE-754 finite in `[0, 1]` (`-0.0` canonicalized to `+0.0`), `[12…15] normalizedY: Float32` IEEE-754 finite in `[0, 1]`, `[16] visible: UInt8` (`0` or `1`). Receivers drop non-increasing `sequence`. |
| `6` (`audio`) | `s2r` | **`16 + N` bytes** (`udpAudioV1`, requires `fragIndex == 0 && fragCount == 1`; also carried in base64 over `tcpAudioV1`): `[0…3] audioSeq: UInt32` (monotonic wrap-safe), `[4…11] captureTimestampMs: Int64`, `[12…13] sampleRate: UInt16` (`> 0`, default `48000`; strictly `48000` for Opus), `[14] channels: UInt8` (`1` or `2`), `[15] formatFlags: UInt8` (`0` = S16LE interleaved PCM with `N % (channels * 2) == 0`; `1` = Opus packet when `audioOpusV1` is negotiated), `[16…16+N−1] payloadBytes` (`1 <= N <= 1152`; receiver ring buffers cap playback at `120 ms` = `5,760` stereo frames @ `48 kHz`). |

FEC overhead (`5%`–`20%` by observed loss, at least `12%` on keyframes) is deducted from the total network budget before setting encoder bitrate. The sender pacer ticks every `1 ms` at `1.2×` pre-FEC target (`maxQueuedPackets = 2048`, `maxQueuedAudioPackets = 16`) with strict dequeue priority `cursor > audio > retransmit > keyframe > normalVideo > fecParity`. Incomplete UDP frame reassembly is bounded by `UDPJitterBuffer` (`3` frames / `45 ms` on Apple) and Android `JitterBuffer` (`4` frames / `35 ms`).

### TCP audio (`tcpAudioV1`), Opus (`audioOpusV1`) and A/V lip-sync

When the sender enables system audio and the authenticated receiver advertises `tcpAudioV1` without an active `udpMediaV1` session (wired USB over `usbmux`, `adb forward`, or `AOA 2.0`, as well as UDP-blocked networks or post-timeout TCP fallbacks), the sender wraps the exact `UDPMediaAudioPayload` bytes in a framed JSON control message:

```json
{"type":"audioFrame","payload":"<base64 UDPMediaAudioPayload>"}
```

`TCPAudioFrameMessage` enforces `<= 4,096` UTF-8 bytes (`base64` string `<= 2,048` ASCII chars). `TCPAudioBackpressurePolicy` drops outgoing TCP audio frames immediately without queuing whenever `pendingSends > 2` or `pendingTCPAudioSends >= 2`, preventing audio from stalling video or input. UDP↔TCP handovers preserve a single monotonic `audioSeq` on the sender and connection-scoped audio players on Mac, iOS, and Android.

When the receiver advertises `audioOpusV1`, `AudioCapturePacketizer` encodes `20 ms` (`960` stereo frames @ `48,000 Hz`, `128 kbps`) Opus frames via Apple `AudioConverter` (`kAudioFormatOpus`, `formatFlags = 1`), falling back automatically to `5 ms` (`240` stereo frames = `960 B`) S16LE PCM (`formatFlags = 0`) if unavailable or unadvertised. Apple receivers decode Opus synchronously via `AppleOpusAudioDecoder` (`AudioConverter`); Android `UdpAudioPlayer` decodes Opus via `MediaCodec` (`MIMETYPE_AUDIO_OPUS`) configured with RFC 7845 19-byte `"OpusHead"` `csd-0` (`48,000 Hz`, `0` pre-skip), 8-byte little-endian `0` ns `csd-1`, and 8-byte little-endian `80,000,000` ns (`80 ms`) `csd-2` with bounded output draining (`OpusPendingTracker`).

Across Mac, iOS, and Android, receiver playback uses a bounded `120 ms` (`5,760` stereo frames @ `48 kHz` = `23,040 B` S16LE) ring buffer. `AudioLipSyncPolicy` (Apple) and `UdpAudioPlayer.LipSyncPolicy` (Android) steer the target playout watermark within `15…90 ms` (`720…4,320` frames; `~45 ms` baseline when UDP jitter buffering is active, `~20 ms` baseline on wired/TCP) using the clock-offset-invariant transit differential `(videoRenderMonoMs - videoCaptureMs) - (audioArrivalMonoMs - audioCaptureMs)`, and trim excess buffered audio whenever queued depth exceeds `target + 25 ms`.

## Control and lifecycle

Common JSON controls include `ping`/`pong`, `stats`, `kf`, `codecFailure`, `udpMediaConfig`/`udpMediaReady`, `cursor`/`cursorImg`, touch/scroll, and receiver closing/sleeping/goodbye messages. Ping timestamps/round trips estimate clock offset and liveness; they do not prove one-way display latency. Cursor images are separately bounded and validated over TCP even when `udpCursorV1` carries `125 Hz` coordinate updates over UDP. `kf` requests a keyframe; Android V2 recovery may include `streamConfigRequired` so a fresh configuration precedes the IDR.

The v0.3.0 Mac 4K latency iteration also sends optional `macReceiverStats` approximately every two seconds. It reports `videoEnqueuedFps`, `backpressureFlushes`, `backpressureToleratedFrames`, `waitingForKeyframe`, `cursorReceived`, `cursorApplied`, `cursorCoalesced`, and `cursorDispatchMaxMs`. Older senders ignore this type. It neither changes framing nor supplies physical rendered FPS or synchronized one-way latency; it is kept separate from Android/iOS `stats` and adaptive-bitrate feedback. See [local evidence](../verification/mac-4k-latency.md).

Mac sender liveness checks run every two seconds and detect more than five seconds of silence; recovery is bounded. iOS also detects five seconds of silence, Mac receiver eight seconds. Protocol admission has its own absolute deadline. A stop, role change, background/sleep or failed connection invalidates the owning generation, cancels input and audio playback, and closes only its resources. Sender and receiver roles on one Mac remain exclusive. Reconnect must repeat authentication, hello and applicable configuration/readiness. See [Mac handover](../guides/mac-lan-handover.md) for same-ID interface transitions; Android ADB recovery remains separate.

The [v0.3.0 Mac recovery iteration](../archive/audits/upstream-integration-2026-10-23.md) adds a 15-second first-video deadline measured with a monotonic clock after connection readiness. Heartbeats, parameter sets and repeated configuration do not satisfy or extend it. A successfully constructed sample submitted to the renderer satisfies it; a static desktop afterward is exempt. A codec/raster change starts a new expectation without extending one already pending. Timeout sends the existing `closing` control and cancels only that socket within 250 ms; the listener remains available. No framing or mandatory control fields change.

## Input extensions

Coordinates are normalized top-left video space. New desktop input uses aspect-fit mapping and ignores black bars; drag release clamps to the picture. Physical macOS key codes use the sender's keyboard layout/input method. Input never implies clipboard/file transfer or global keyboard capture.

**Touch and Pencil V1:** inherited `touch` phases `began`/`moved`/`ended`/`cancelled`, coordinates `x/y`, and `scroll.dx/dy` remain compatible. `pencil-v1` requires explicit hello and `inputConfig` agreement (advertised by iPadOS Apple Pencil receivers and, on the source branch, Android receivers for `TOOL_TYPE_STYLUS` / `TOOL_TYPE_ERASER`). A `pencil` message has `phase` (`down/move/up/cancel/hover`), x/y/pressure in [0,1], azimuth in [−2π,2π] and altitude in [0,π/2], all finite numbers, not JSON booleans. Non-contact phases force zero pressure. A stroke fixes legacy-touch versus native mode when it begins. `proximity` carries entering and normalized position.

**Pencil V2:** additionally negotiate `pencil-v2` over authenticated TLS. `pencil2` retains V1 fields and requires `roll` in [−2π,2π] radians and `tool` of `pen` or `eraser` (mapped from Apple Pencil barrel roll / eraser and Android stylus `AXIS_TILT` / `TOOL_TYPE_ERASER` / primary barrel button). Roll becomes normalized degrees for the Mac tablet event. Tool changes release the previous stroke/proximity. UIKit double tap / completed squeeze and Android secondary stylus button (`BUTTON_STYLUS_SECONDARY`) map locally to tool selection or named actions. See [advanced Pencil](../guides/pencil-advanced.md).

Pencil shortcuts additionally require default-off sender consent and Accessibility. `inputConfig.pencilActionSession` grants a fresh UUID; `pencilActionStatus` explains denial/readiness. Receiver sends `pencilAction` with `inputSession`, strictly increasing integer `sequence` (1…2^53−1) and `action` of `undo`, `redo`, `shortcut1`, or `shortcut2`. Mac owns key/modifier mappings; remote arbitrary keys are not accepted on this channel. At most five actions in a rolling second; rate-limited sequence values are consumed. Connection/target/permission changes revoke grants. Every shortcut cancels tablet input and sends a balanced chord.

**Desktop input (`mac-input-v1`):** authenticated hello advertises `mac-input-v1` (Mac receivers in `v0.3.5+`, plus source-branch iPadOS/iOS receivers for indirect pointer / hardware `UIKey` HID keyboards and Android receivers for external `SOURCE_MOUSE` / `SOURCE_TOUCHPAD` / `SOURCE_MOUSE_RELATIVE` pointers and physical `KeyEvent` keyboards). The sender must opt in and have Accessibility; the receiver must opt in separately. `inputConfig` grants `inputSession` UUID, capability and `inputStatus`. `desktopInput` includes that UUID, strictly increasing integer `sequence` (1…2^53−1), `kind`, and `modifiers`. Modifier bits are Shift 1, Control 2, Option 4, Command 8 and Caps Lock 16; other bits are rejected.

| Kind | Required extra fields |
| --- | --- |
| `move` | x/y in [0,1] |
| `buttonDown`, `buttonUp` | x/y, button 0/1/2 (left/right/middle), clicks 1…3 |
| `scroll` | x/y, dx/dy in [−4096,4096] |
| `keyDown`, `keyUp` | keyCode 0…127 excluding modifier key codes 54…63; optional Boolean `repeat` |
| `modifiers` | Only common fields; modifiers represent the aggregate state |
| `releaseAll` | Only common fields; releases owned keys/buttons/modifiers |

At most 16 regular keys and three buttons can be held. Duplicate/stale grant sequences are ignored. Invalid shapes cancel the active grant/state. Input captures only the focused receiving video view; focus loss, scene deactivation, disable, close, role changes and disconnect emit `releaseAll` and clear local state. Control–Option–Escape disables or releases desktop input forwarding locally on Mac and source-branch iPadOS/iOS receivers. Consent/permission is checked per event and within two seconds during idle. OS permission withdrawal can prevent synthetic release delivery, but owned state is always cleared. See [Mac input](../guides/mac-receiver-input.md).

## Shared fixtures and verification

[`wire-contract-v1.properties`](../../tools/fixtures/wire-contract-v1.properties) contains public synthetic, hexadecimal vectors for outer framing, legacy telemetry, H.264/HEVC DWV2, invalid versions/flags/identity/lengths, desktop/Pencil input (`desktopPayload`, `pencilPayload`, `actionPayload`), 14 Revision 2 `udpMediaV1` vectors (`udpRootSecret`, `udpS2RKeyEpoch1`, `udpS2RSaltEpoch1`, `udpR2SKeyEpoch1`, `udpR2SSaltEpoch1`, `udpS2RNonceSeq1`, `udpR2SNonceSeq1`, `udpHeaderVideoData`, `udpHeaderCursor`, `udpHeaderAudio`, `udpCursorPayload`, `udpAudioPayload`, `udpCursorSealedDatagram`, `udpAudioSealedDatagram`), and 6 Revision 3 audio/Opus vectors (`udpAudioOpusPayload`, `tcpAudioPayload`, `tcpAudioFrame`, `opusHead48kStereo`, `opusCsd1PreSkip`, `opusCsd2SeekPreRoll`). Swift `WireContractSelfTest` and Java `WireContractSelfTest` consume the exact same bytes and actual production parsers/encoders alongside Swift `UDPMediaProtocolSelfTest`, `UDPMediaFECSelfTest`, `UDPMediaEngineSelfTest`, `UDPMediaTransportSelfTest`, `UDPDelayGradientBWESelfTest`, `AudioVisualFidelitySelfTest`, `USBAccessorySelfTest`, `CaptureFramePolicySelfTest`, `ReceiverSceneLifecyclePolicySelfTest`, `MacCoreUpgradeSelfTest`, and Android Java `ProtocolSelfTest`, `UsbAccessorySelfTest`, `ReceiverConnectionSelfTest`, and `VideoStreamPolicySelfTest`. Swift exercises every split boundary and coalescing; Java exercises one-byte reads, coalescing and truncated EOF.

[`secure-pairing-v1.properties`](../../tools/fixtures/secure-pairing-v1.properties) is the shared auth/invitation/ready corpus. Real Apple↔Java TLS and production receiver runtime suites supplement the byte fixtures. Golden vectors do not replace permission, role/lifecycle, native key-storage or hardware tests.

```sh
./tools/run-swift-self-tests.sh
(cd AndroidReceiver && ./gradlew --no-daemon test assembleDebug lintDebug)
python3 tools/test-tls-interop.py
python3 tools/test-apple-keychain.py --ios-simulator
python3 tools/test-secure-ios-receiver.py
python3 tools/test-secure-android-receiver.py
pnpm run check:docs
```

The normative source contracts are `Shared/ReceiverFrameDecoder.swift`, `Shared/SecurePairingProtocol.swift`, `Shared/UDPMediaProtocol.swift`, `Shared/UDPMediaFEC.swift`, `Shared/UDPMediaEngine.swift`, `Shared/UDPMediaTransport.swift`, `Mac/USBAccessory.swift`, `Mac/AccessoryDeviceWatcher.swift`, `Mac/AndroidUSBFunction.swift`, `Mac/AudioCapturePacketizer.swift`, `Mac/CaptureFramePolicy.swift`, `Mac/VirtualDisplay.swift`, `Mac/DeviceCapabilities.swift`, `Mac/StreamEncodingPolicy.swift`, `Mac/BinaryFrameHeaderV2.swift`, `Shared/AppleVideoPolicy.swift`, `Shared/PencilProtocol.swift`, `Shared/PencilActions.swift`, `Shared/DesktopInputProtocol.swift`, `iOS/ReceiverSceneLifecyclePolicy.swift`, and Android `protocol/LengthPrefixedProtocol.java`, `protocol/BinaryFrameHeaderV2.java`, `protocol/UdpMediaProtocol.java`, `protocol/AndroidStylusInput.java`, `protocol/AndroidDesktopInput.java`, `UsbAccessoryReceiverTransport.java`, `UdpMediaReceiverSession.java`, `UdpAudioPlayer.java`, `H264SurfaceDecoder.java`, `SecurePairingProtocol.java`, and `ReceiverProtocolSession.java`.

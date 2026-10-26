[English](android-binary-frame-header-v2.md) | [简体中文](android-binary-frame-header-v2.zh-CN.md)

# Android binary frame header V2 and allocation path

## Modified files

- `Mac/BinaryFrameHeaderV2.swift`, `Mac/DeviceCapabilities.swift`, and `Mac/MacSender.swift` add the gated encoder and legacy fallback;
- Android protocol/frame packet, Annex-B, server, decoder, and metrics code add bounded parsing and zero-copy payload views;
- protocol, video-policy, capability, header, and Benchmark standalone tests cover the contract;
- Benchmark CSV/JSONL and bilingual architecture/index documents expose the new evidence.

## Purpose

PR 9 replaces the per-frame JSON telemetry prefix only when an Android receiver independently advertises `binaryFrameHeaderV2`. It carries identity, timestamps, codec/keyframe flags, and payload length in a fixed header while retaining the existing outer four-byte length prefix and Annex-B codec payload.

Legacy OpenDisplay iOS, old Android, partial V2 advertisements, and complete core V2 peers without the independent capability keep the existing JSON telemetry prefix plus Annex-B bytes. The binary header is never sent merely because `protocolVersion` is 2.

## Wire contract

All integer fields use network byte order. The existing outer frame is still `[UInt32 length][payload]`; the following 52-byte header is the negotiated Android payload prefix:

| Offset | Bytes | Field |
| ---: | ---: | --- |
| 0 | 4 | magic `DWV2` (`44 57 56 32`) |
| 4 | 1 | version `2` |
| 5 | 1 | flags |
| 6 | 2 | header length `52` |
| 8 | 8 | session epoch |
| 16 | 8 | config version |
| 24 | 8 | frame sequence |
| 32 | 8 | capture timestamp, Unix milliseconds |
| 40 | 8 | send timestamp, Unix milliseconds |
| 48 | 4 | Annex-B payload length |
| 52 | variable | Annex-B payload |

Flags are `KEYFRAME = 0x01`, `CODEC_CONFIG = 0x02`, `HEVC = 0x04`, and `H264 = 0x08`. Exactly one codec flag is required. Unknown versions, unknown/conflicting flags, non-positive identity, invalid header/payload lengths, truncation, and payloads above the absolute 16 MiB safety ceiling are rejected before decoder input.

## Capability and compatibility rules

- Android Hello advertises `binaryFrameHeaderV2` separately from the six core V2 progress/identity capabilities and `maxFrameBytes`.
- Mac enables the header only when the peer is Android, the complete core V2 set is present, and the independent binary capability is present.
- Core Protocol V2 remains usable without this feature and then retains JSON telemetry framing.
- Every VideoToolbox encode is bound to the ready connection generation that accepted it. A callback arriving during disconnect or after reconnect is dropped before framing, so stale in-flight output cannot reach a new Android or Legacy iOS session.
- Codec flags must match the accepted StreamConfig; identity rejection remains ahead of codec rejection so stale frames retain the correct stale epoch/version reason.

## Allocation and NAL-scan changes

- The Android length reader no longer allocates a separate four-byte header array.
- `VideoFramePacket` retains the transport `byte[]` and passes an offset/length view into MediaCodec; JSON telemetry stripping no longer copies the encoded frame.
- Binary fields are parsed directly from bytes, avoiding a per-frame JSON `String`.
- Binary flags avoid keyframe/codec-config NAL scans after decoder configuration.
- Legacy classification uses one `NalSummary`; decoder configuration reuses it and copies only VPS/SPS/PPS when MediaCodec actually needs codec-specific data.
- Error-only NAL descriptions scan ranges without allocating a list and one `byte[]` per NAL.

The original PR 9/p8 transport allocated its bounded outer payload array. Source builds after p8 now use a transport-wide pool: at most 32 MiB / 32 buffers, power-of-two buckets starting at 1 KiB, frame lengths at most 16 MiB (subject to the lower negotiated limit). A saturated pool waits at most 250 ms before closing the affected connection for recovery. Idle buckets can be evicted; active storage is never reused.

Transport callbacks borrow a lease; executor tasks, pending video and asynchronous decoder input each retain a separately closeable reference. Queue replacement, stale generation, parse failure, executor rejection/shutdown, decoder reconfiguration and disconnect release their owned references. After copying into the MediaCodec input buffer, the decoder returns its reference. Closing a pool discards idle buffers immediately and in-flight buffers on their final return. The valid wire length is separate from bucket capacity, including legacy JSON/Annex-B frames.

Per-window `allocatedFrameBytes` now counts newly allocated bucket bytes, `bufferReuseCount` counts actual idle-pool reuse, and `bufferPoolMiss` counts new arrays. They include accepted transport control frames as well as video, and retain their existing wire/Benchmark field names. **Do not compare these counts directly with p8**, where reuse meant a zero-copy payload view and every frame counted as a miss. Android runtime `gcCount`/`gcTimeMs` semantics are unchanged.

## Tests

- failure-first Java tests cover round trip, exact identity/timestamps/flags, unknown version, malformed header length, conflicting codec flags, invalid and oversize payload lengths, truncation, and Legacy fallback;
- failure-first Swift tests cover encoder/decoder round trip and invalid version/flags;
- capability tests prove Legacy iOS and missing/partial advertisements cannot enable the header while core V2 remains independent;
- packet tests prove binary and legacy payloads retain the original transport array and that codec mismatch is observable;
- NAL tests prove one summary reports parameter sets/keyframes through source ranges;
- metrics tests cover allocation/reuse/pool-miss fields and stable Benchmark columns/JSON.

## Original PR 9 build result

- Focused Android Protocol and VideoStream policy self-tests: passed.
- Focused Swift Binary Header, Device Capability, and Benchmark self-tests: passed.
- Android clean/test/Debug assembly: passed, `61 actionable tasks: 61 executed`; Protocol, Receiver Connection, Receiver Lifecycle, Update Policy, Update Verifier, and Video Stream self-test groups all passed.
- All 22 standalone Swift self-tests passed, including the new binary-header round trip and legacy-fallback contract.
- `xcodegen generate`, unsigned macOS Debug build, and generic iOS Simulator Debug build passed.
- Production site build/prerender, 32 bilingual document pairs, release-link validation, and `git diff --check` passed.
- `adb devices -l` reported no attached device, so the physical matrix below remains pending.

## Before/after metrics

No same-condition physical A/B has been collected. This PR proves fewer software copies/scans by code path and tests, but does not claim lower Frame Age, lower GC time, or higher rendered FPS. The added counters make those claims testable later.

## Known risks

- Flags are trusted only after local capability negotiation and are still bounded/validated; a corrupt Annex-B payload can be rejected by the decoder path.
- The 52-byte inner header slightly reduces usable encoded payload under the existing negotiated outer frame limit.
- Pool saturation intentionally closes the affected connection rather than falling back to unbounded allocations; physical burst/memory behavior still needs acceptance.
- Runtime GC keys are platform-provided; unavailable keys report zero rather than inventing data.

## Pending physical validation

- Android WiFi and ADB USB HEVC/H.264 connection with the negotiated header;
- confirm Ack, Decoder Ready, First Frame, reconnect, transport switch, and stale-frame rejection;
- compare per-window `allocatedFrameBytes`, reuse/miss counts, GC count/time deltas, Frame Age P50/P95/P99, rendered FPS, and decoder drops under the same scene;
- recheck an old Android build and the Legacy OpenDisplay iOS Receiver to prove byte-for-byte fallback behavior.

No physical receiver was attached during implementation.

## Next step

Run the final requirement-by-requirement compatibility/recovery audit and the available short physical matrix without claiming deferred endurance or multi-device coverage.

## Source pooling verification (2026-10-16)

Plain-Java tests cover retained async ownership, pool saturation, double close, partial-read failures, invalid lengths before allocation, binary/legacy bucket tails, task cancellation/rejection/exception, concurrent leases, real TCP replacement and late returns after shutdown. A synthetic sequence of 1,000 equal 1,000-byte frames allocated one 1,024-byte bucket: 1 miss and 999 pool reuses. This measures the software allocation path only; it is not a physical GC, latency or FPS result. Android six self-test groups and Debug assembly passed.

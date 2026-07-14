[English](current-memory-gc-buffer-audit.md) | [简体中文](current-memory-gc-buffer-audit.zh-CN.md)

# Current Memory, GC, and Buffer Ownership Audit

Baseline: `79cbf90`; physical profiling: **Pending**.

## Current allocation path

1. `LengthPrefixedProtocol.readExact` allocates one outer `byte[]` per frame.
2. Binary V2 `VideoFramePacket` owns a zero-copy offset/length view of that array.
3. Legacy parsing reuses the same outer array but scans the JSON/Annex-B boundary.
4. NAL summary retains offsets into the same array; VPS/SPS/PPS are copied only for codec configuration.
5. Decoder input copies payload bytes into the MediaCodec-owned input buffer.
6. Swift constructs Annex-B `Data`, wire header/prefix `Data`, and the four-byte outer framing `Data`.

`allocatedFrameBytes`, zero-copy `bufferReuseCount`, and `bufferPoolMiss` are per publication window. ART GC runtime counters were cumulative but were previously emitted as ambiguous window fields; they now publish reset-safe per-window deltas under `gcCount` and `gcTimeMs`, with deterministic delta tests.

## FrameBufferPool design gate

No pool is implemented. A safe future pool requires one owner token spanning TCP read → latest slot → decoder submission, return on slot replacement/rejection/submission, generation invalidation on reconnect, and protection against return while any packet/NAL view still references the array. Capacity, maximum retained size, oversize bypass, pool misses, and use-after-return assertions must be specified before implementation. Frame-render callbacks do not need the compressed payload and must not extend buffer ownership beyond successful input submission.

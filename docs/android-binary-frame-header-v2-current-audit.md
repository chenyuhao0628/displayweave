[English](android-binary-frame-header-v2-current-audit.md) | [简体中文](android-binary-frame-header-v2-current-audit.zh-CN.md)

# Binary Frame Header V2 and Legacy Audit

Baseline: `79cbf90`; physical Legacy compatibility: **Pending**.

The Swift and Java implementations agree on magic `DWV2`, version 2, a fixed 52-byte network-order header, flags, three positive identity fields, non-negative timestamps, and a payload length contained inside the 16 MiB outer absolute bound. Conflicting/missing codec flags, unknown flags/version, invalid header length, non-positive identity, truncation, payload mismatch, and oversize payload are rejected.

The receiver additionally rejects Binary V2 unless core protocol V2 was negotiated and verifies the codec flag against the active StreamConfig. The sender enables Binary V2 only when Android advertises the complete core V2 capability set plus the independent `binaryFrameHeaderV2` capability. Legacy iOS, partial capability sets, unknown/core-only V2 sets, and missing identities retain JSON-prefix framing.

Automated tests include a byte-for-byte Legacy assertion (`{"cap":1000,"snd":1010}` followed by unchanged Annex-B bytes), malformed input cases, zero-copy payload views, and capability gating. Protocol-level compatibility is verified; physical old iOS/Android runtime compatibility is Pending.

No new protocol defect was found in this phase. The transport still allocates one outer payload array per frame; no buffer pool is claimed or implemented.

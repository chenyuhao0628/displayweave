[English](current-code-audit-report.md) | [简体中文](current-code-audit-report.zh-CN.md)

# Current Code Audit Report

Generated: 2026-07-15 (Asia/Shanghai)  
Audited HEAD: `79cbf90fdc61bf296a222a10750b2fa7f0a2df1f`  
Preview 5 target: `4276c1a229f9f0b3237242d3ebbc0f29d7e244da` (audited HEAD is two commits ahead)  
Worktree at baseline: clean  
Physical validation: **Pending — `adb devices -l` returned no attached devices**

## First-round answers

1. **Could old async MediaCodec callbacks contaminate current state? Yes (P0).** Input/output/error/format callbacks checked codec identity, but frame-rendered callbacks did not. Since timestamps restart at zero, an old callback could consume current telemetry. Callback generation checks have now been added to every callback path.
2. **Was input-buffer index ownership strict? No (P1).** The queue had no duplicate guard. An ownership set has now been added and is cleared with the queue on every lifecycle boundary.
3. **Can pending P-frame replacement break the reference chain? Yes in principle; the remediated policy handles it explicitly.** It enters keyframe-wait state, rejects dependent frames, requests one recovery, and recognizes H.264 IDR plus HEVC IRAP 16–23 including CRA.
4. **Could `renderedTelemetry` grow without bound? Yes (P0).** It is now capped at 512 with oldest-entry eviction and peak/eviction counters.
5. **Can combined pending-work accounting be wrong? It could before remediation (P1/P2).** Work is now owned by an immutable encoder generation; old completions cannot decrement or enter the current codec, duplicate/unmatched completions are rejected, and the pre-encode combined budget remains unchanged.
6. **Does the advertised decoder cap match the selected path? It did not reliably; the static mismatch is locally fixed.** Advertisement now follows default runtime candidate ordering and, for HEVC preference, uses the common supported cap of selected HEVC and selected H.264 fallback paths. Vendor misreport/runtime fallback remains physical Pending.
7. **P0/P1 found? Yes.** Two P0 and the identified static P1 defects were locally remediated and covered by deterministic policy/state tests. Hardware/vendor behavior remains Pending rather than closed by source tests.
8. **Code-only / no physical evidence:** asynchronous callback behavior, low-latency MediaCodec, WiFi low-latency locks, Surface frame-rate lifecycle, 90/120Hz mapping, decoder capability limits, USB/WiFi takeover, codec fallback, Binary V2 runtime, thermal/power metrics, real rendered FPS/latency/recovery, and Legacy iOS/old Android compatibility.
9. **Recommended first PR:** “Async MediaCodec ownership and stale callback safety.” Keep it limited to callback generation, input-index ownership, bounded telemetry, deterministic tests, and terminal-error handoff. Do not combine it with FPS/ABR/protocol changes.

## Severity summary

| ID | Severity | Status | Summary |
| --- | --- | --- | --- |
| ADC-001 | P0 | locally fixed | stale frame-rendered callback accessed shared current telemetry |
| ADC-002 | P0 | locally fixed | unbounded rendered telemetry map |
| ADC-003 | P1 | locally fixed | duplicate input index not rejected |
| ADC-004 | P1 | locally fixed; physical Pending | terminal codec error enters coalesced rebuild/fallback recovery |
| REF-001 | P1 | locally fixed + tested | HEVC IRAP/CRA recovery classification |
| WB-001 | P1 | locally fixed + tested | pending encode and stale callback accounting is encoder-generation scoped |
| FPS-001 | P1 | locally fixed; physical Pending | advertised capability follows default runtime candidate ordering |
| FPS-002 | P1 | locally fixed conservatively | advertised cap is valid across selected HEVC and H.264 fallback paths |
| MET-001 | P2 | locally fixed + tested | cumulative GC counters mislabeled as window metrics |
| WB-002/3/4 | P2 | partially fixed/Pending | unmatched completion telemetry added; ABR fields and budget A/B remain Pending |

## Confirmed active-path implementation

Code and automated tests confirm Connection Generation, independent accept/read loops, current-socket takeover, Session Epoch, Config Version, Frame Sequence, V2 progress acknowledgements, Legacy fallback, keyframe coalescing, negotiated frame limits, decoder/WiFi low-latency modes, Surface frame-rate lifecycle, Drop attribution, local fast bitrate decrease, Binary Header V2 zero-copy views, thermal/power metrics, asynchronous MediaCodec, latest pending compressed frame handling, reference-chain recovery, decoder capability capping, and 90→higher-refresh mapping. These are implementation findings, not physical performance claims.

Protocol-level Legacy compatibility is verified by capability gating and byte-for-byte framing tests. Physical Legacy OpenDisplay iOS and old Android compatibility is Pending.

## Identity boundary review

| Event | Required identity | Result |
| --- | --- | --- |
| Transport callback | Connection Generation | enforced by transport context and coordinator |
| StreamConfig | Generation + Session Epoch + Config Version | enforced for V2 |
| Video frame | Generation + Epoch + Config + Sequence | enforced for V2; Legacy fallback intentionally lacks V2 identity |
| Decoder callback | Decoder Generation + active codec/session | decoder generation fixed locally; server listener checks connection/session/config |
| First frame | Epoch + Config + Sequence | enforced for V2 through telemetry; physical evidence Pending |
| Stats | Current session only | generation/session delivery guarded; Drop windows and GC deltas reset explicitly |

Connection A's late reader/writer/disconnect events are rejected after B becomes current. Decoder listener events are serialized and recheck generation/session/config. The pre-fix frame-rendered callback was the exception inside the decoder and is the main reason the first remediation must land first.

## Automated evidence

Executed from `AndroidReceiver`:

```text
./gradlew --no-daemon clean test assembleDebug
BUILD SUCCESSFUL
ProtocolSelfTest PASS
ReceiverConnectionSelfTest PASS
ReceiverLifecycleSelfTest PASS
UpdatePolicySelfTest PASS
UpdateVerifierSelfTest PASS
VideoStreamPolicySelfTest PASS
```

The extracted decoder callback state deterministically covers old generation rejection, duplicate input index ownership, lifecycle clearing, and bounded telemetry. Real vendor `MediaCodec` callback timing and Surface races remain physical/instrumentation Pending.

Additional verified gates:

- `tools/run-swift-self-tests.sh`: all 22 standalone suites pass.
- macOS Debug build: succeeded.
- unsigned iOS Simulator compatibility build: succeeded.
- `pnpm build`, `pnpm run check:docs`, `pnpm run check:release`, and `git diff --check`: passed.
- Preview 5 remote tag, successful release workflow, seven assets, SHA256SUMS, APK v2 signer/version, Mac build/version, immutable ZIP appcast, Android manifest, and live Pages feeds: independently verified. DMG checksum passed; local mount-layout verification is environment-Pending.

## Release recommendation

Do **not** describe Preview 5 as physically validated or production-stable. The static P0/P1 corrections are ready to split into the recommended focused PRs, but the next preview should wait for the requested WiFi/USB, codec, refresh-rate, recovery, and Legacy physical matrix or explicitly ship with those items prominently marked Pending.

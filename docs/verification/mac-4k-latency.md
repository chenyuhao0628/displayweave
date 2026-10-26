[English](mac-4k-latency.md) | [简体中文](mac-4k-latency.zh-CN.md)

# Mac 4K latency: source changes and local evidence

Date: 2026-10-23. Included in [v0.3.0 stable (19)](../archive/releases/release-notes-v0.3.0.md), native source `929eb93`. This audit records local evidence; it does not guarantee Intel 4K60 performance.

## Scope and implementation

Keep the selected 3840×2160 desktop/encoding resolution, codec preference, and 60 FPS target. A report of sender-mouse lag between two Intel iMacs over Ethernet prompted this work. The supplied successful sessions requested low-latency H.264 and independent cursor echo. Encoder-startup fallback, first-video failure and capture/display recovery are now implemented in the follow-up [upstream integration](../archive/audits/upstream-integration-2026-10-23.md).

- Allow two encodes in flight at 60 FPS, as already allowed at 90/120 FPS. One slot unnecessarily skips alternate captures when asynchronous completion takes longer than 16.7 ms. The limit stays two; a slower encoder still applies backpressure.
- Sample the pointer on an independent interactive queue every 8 ms, with one transport write in flight and one replaceable pending position. Remove the normalized 0.0004 movement deadband, approximately 1.5 pixels horizontally at 4K. Keep the existing authenticated TCP connection and framing; give unsent cursor messages higher relative priority than video. Already-submitted TCP bytes cannot be overtaken.
- Coalesce receiver cursor delivery to the newest point while the main thread is busy. Coalesce sprite work too, and reject retired delivery tokens and sprite generations across session replacement.
- Assign interactive QoS to Mac video/receive processing and the interactive-video network service class to the sender, matching the receiver. Both ends already used TCP no-delay; interface pinning remains unchanged.
- Record the actual path interface type, encoder property/query results, capture/encode/send rates, encode submission blocking, and cursor coalescing/dispatch statistics. New Mac receiver statistics return to the sender so its existing log can include both ends. No desktop pixels, key events, cursor coordinates, or private peer identifiers are added to these diagnostics.

`EnableHardwareAcceleratedVideoEncoder` explicitly prefers hardware without requiring it for H.264. Hardware availability, requested properties, and successful encoder creation are distinct from proof of which encoder ran. Unsupported property queries are reported as unknown.

## Automated verification

| Exercise | Before | After |
| --- | --- | --- |
| 600 captures at 60 Hz, simulated 19/23/28 ms asynchronous completions | 300 admitted | 600 admitted |
| 240 cursor messages over real loopback TCP while the main thread is blocked | 240 callbacks replayed | 1 callback with the latest position |
| Transport completion stalled while pointer samples continue | Previously no cursor-write budget | 1 write in flight, latest pending sample retained |
| Retired work completes after replacement | New regression coverage | Replacement work is not drained or cancelled |

A separate real loopback test sends 48 ordered 256 KiB video payloads concurrently with prioritized cursor messages through the production writer and frame decoder; framing and video ordering remain intact.

The cadence table is a deterministic scheduling model, **not measured display FPS**. Regression tests failed on the old policy/delivery code before the fixes. The 55 Swift suites include real Mac receiver TCP/TLS, malformed frames, reconnects, input consent, and the new cursor/diagnostic cases. Mac Debug compiles for arm64 and x86_64. A universal build does not execute Intel drivers.

The cursor relay/sampling regression also passes under Thread Sanitizer, with no reported data races.

Run `./tools/run-swift-self-tests.sh` and the unsigned universal build documented in [development](../development/workflow.md). The opt-in `python3 tools/run-mac-4k-probe.py` compiles a bounded offscreen probe and encodes 180 synthetic moving-block frames per run at 3840×2160, H.264, a 60 FPS target and 49,766,400 bps target bitrate. It compares the old one-slot/zero-delay limit with the production two-slot/one-frame-delay policy. Pass `--bitrate-mbps 100` to exercise a 100 Mbps target. It uses no screen capture, virtual display, GUI window, or user preferences.

On the local **arm64 / macOS 26.5.2** host, both runs encoded 180/180 frames, approximately 60 FPS, with zero failed or skipped frames. This host did not demonstrate a cadence improvement because its callbacks fit within one 60 Hz interval. `MaxFrameDelayCount` and `PrioritizeEncodingSpeedOverQuality` returned unsupported-property status (-12900); the hardware query returned unknown. These results demonstrate the local synthetic workload only, not complex desktop rendering, receiver presentation, or Intel performance.

The additional 100 Mbps **target** probe also encoded 180/180 frames in both runs, with zero skipped/failed frames: approximately 60.02 FPS for the old policy and 60.04 FPS for the new policy. The same unsupported-property results remain. This tests encoder configuration under a simple synthetic scene; it does not measure 100 Mbps of actual traffic or Ethernet capacity. That latency round's 55-suite regression, unsigned universal Mac build, 93 bilingual-document pairs, release-link check and whitespace check passed. The follow-up upstream integration passes 60 suites and a new unsigned universal Mac build. Standalone test compilation retains existing CVDisplayLink deprecation warnings; the Mac app build reports no warnings.

## Second audit: conservative limits and recovery

The second source review found four reproducible restrictions:

| Path | Previous behavior | Source change |
| --- | --- | --- |
| Encoder submission | `MaxFrameDelayCount = 0` requires frame N to be emitted before submission of N returns on encoders that support it. Increasing only the external encode budget cannot remove that serialization. | Match the two-slot budget with `MaxFrameDelayCount = 1` at 60/90/120 FPS; keep zero at 30 FPS. Real-time encoding and no B-frames remain enabled. Record both requested delay and property status. |
| Mac renderer occupancy | Every not-ready observation flushed the decoder and discarded dependent frames until a keyframe. | Permit at most two additional frames while not ready, within 50 ms of the first observation. Then flush once and wait for readiness plus a keyframe. Real decoder failure still follows the existing failure/fallback path. |
| Mac automatic bitrate | Local send pressure could decrease bitrate, but recovery existed only in the phone `stats` handler, which Mac receivers do not use. | Enable local recovery for Mac peers: after five seconds of active, drained send windows, increase by 7%, up to the original target. Idle windows, gaps over one second and manual mode do not establish recovery. Phone receiver policies stay separate. |
| Apple configuration FPS | `exactFrameRate` serialized an already negotiated 90/120 FPS as 60. | Preserve the negotiated value, bounded to 1…120. This fixes the configuration contract; it does not raise the 4K decoder envelope or explain a 60 FPS incident. |

All four new regressions failed before their fixes. The submission model admits 300/600 captures with a zero-delay requirement at simulated 19/23/28 ms completion, and 600/600 with the bounded pipeline. This models the documented submission contract, not measured Intel throughput. The receiver regression sends real encoded H.264 I/P samples over loopback TCP into the production parser, using an injected renderer to reproduce short/sustained pressure, the 50 ms bound, keyframe recovery, replacement and actual failure status. It does not simulate physical display timing. The bitrate regression previously remained at 44 Mbps after a temporary drop from 50 Mbps; it now restores 50 Mbps without exceeding that target.

Apple API semantics were checked against the installed SDK headers `AVQueuedSampleBufferRendering.h` (not-ready occupancy may still accept bounded samples) and `VTCompressionProperties.h` (submission delay and data-rate contracts). The two-frame/50 ms allowance is a bounded source policy, pending physical latency validation.

The remaining limits and the requested bitrate change were reviewed as follows:

- The Apple envelope of `4096 × 2304 × 60` pixels/second permits both reported 3840×2160/60 and 4096×2304/60 streams. HEVC's H.264 fallback envelope preserves a decodable same-resolution fallback.
- TCP uses the legacy `wifi` bitrate-policy category for both Ethernet and Wi-Fi. At the user’s request, the v0.3.0 H.264 LAN ceiling is raised from 60 to 100 Mbps, exposing Manual 80/100 Mbps and retaining a hard 100 Mbps bound outside Benchmark mode. This applies to all receivers on this LAN policy, not only Intel Macs. The automatic 4K60 high-quality estimates remain approximately 49.77 and 56.62 Mbps; raising the ceiling does not force those sessions to 100 Mbps or prove better cadence. The new preset/clamping regressions failed under the old 60 Mbps limit. See [bitrate modes](../reference/bitrate-modes.md).
- The one-second hard `DataRateLimits` cap equals the average bitrate target. The SDK notes that a target close to a hard cap can undershoot. Additional burst headroom is a candidate for measured encoder/quality testing; it has not been enabled without workload or link-rate evidence.
- Capture queue depth eight, video send budgets, one cursor write plus latest pending position, frame-size checks, session generations and codec limits remain bounded. Increasing these limits without evidence can add retained work rather than improve responsiveness.

## Diagnostics and remaining physical verification

- `TRANSPORT-PATH`: whether the established route uses Ethernet or Wi-Fi. It does not measure cable link speed or prove physical topology.
- `ENCODER-IMPLEMENTATION`: hardware/encoder identity when queryable and status codes for selected property requests.
- `PIPELINE-STATS`: approximately two-second capture, encode and send rates, drops, pending work, measured throughput, last send completion delay and maximum synchronous encode-submit duration.
- `CURSOR-SEND`: changed/coalesced/completed position counts, sampling gaps and completion delay, approximately every two seconds during activity.
- `MAC-RECEIVER-STATS`: receiver enqueue rate, decoder backpressure flushes and tolerated frames, cursor received/applied/coalesced counts and maximum local dispatch wait. It is not physical screen FPS or synchronized one-way latency.
- The follow-up adds `ENCODER-ATTEMPT` plus selected-mode logs, `FIRST-VIDEO-TIMEOUT`, `CAPTURE-RECOVERY`, `CAPTURE-SOURCE-MISMATCH` and `DISPLAY-UNIT-RECOVERY` to identify startup refusal, missing video, recovery waits, wrong capture source and display-number conflicts.

**SKIP:** two Intel iMacs on macOS 15, real direct-cable throughput, 4K screen capture and visible rendering, and long-session latency/endurance. The two affected Intel machines were unavailable locally; screen-capture/window/virtual-display tests were not run. No WindowServer or remote-access service was restarted.

Shared TCP still permits cursor delay behind bytes already submitted for video; Network.framework completion is not a remote-display acknowledgement. Independent cursor sampling therefore does not guarantee 120 Hz presentation or eliminate all network/decoder latency. Separate transport negotiation and a guaranteed 4K60 operating point remain outside this source change; encoder-initialization fallback is now implemented and covered by injected-failure tests in the linked upstream integration. Once packaged, a brief check under the user's normal 4K workload plus the enriched sender log is preferable to repeated codec/resolution permutations.

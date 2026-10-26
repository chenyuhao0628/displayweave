[English](upstream-integration-2026-10-23.md) | [简体中文](upstream-integration-2026-10-23.zh-CN.md)

> Historical record: versions, commands and conclusions describe the original snapshot. Use the [current documentation](../../README.md) for present-day instructions.

# Upstream Mac recovery integration — 2026-10-23

Implemented in native source commit `929eb93` on `codex/4k-wired-latency`, based on `39f97a5`, and included in [v0.3.0 stable (19)](../releases/release-notes-v0.3.0.md). It extends the [4K latency work](../../verification/mac-4k-latency.md). The evidence below does not establish Intel 4K60 performance.

## Verified upstream baseline

Fetched `origin` (`peetzweg/opendisplay`) and checked GitHub's release API on October 23, 2026. The working remote remains `displayweave` (`chenyuhao0628/displayweave`).

- Latest upstream release: [v1.26.0](https://github.com/peetzweg/opendisplay/releases/tag/v1.26.0), published **2026-10-22 16:08:45 UTC** (2026-10-23 00:08:45 in Beijing), target `f95054798261edad0654f078f9b3ea6d63f99137`. Its main addition is the Linux sender/receiver beta.
- Reviewed upstream main: `6f4b474bee767ca377a76a03a59c57153b310b2f`, committed 2026-10-22 17:23:16 UTC; **18 commits** after the previously reviewed `b9eec1f232fb5ea571c87e8392379a84f47b237f`.
- Mac fixes `1522cd2`, `cde4fc8` and `5de4252` follow the release target. Their presence on main is not evidence that v1.26.0 binaries contain them. Upstream and DisplayWeave version numbers are independent.

This is a selective source adaptation with per-change review, not a whole-history Git merge. GPL-3.0 and upstream attribution are retained.

## The original three findings

The earlier latency work had **not** fixed these three source defects. This iteration does:

1. **Unsupported low-latency encoder creation:** try the preferred codec with the requested low-latency mode, then the same codec without it. Only then try H.264 if HEVC was preferred. At most four attempts; an explicitly disabled preference stays disabled. Failed creation or preparation releases the temporary session. Logs distinguish the requested and selected modes.
2. **Encoder failure without pipeline failure:** creation/preparation now throws. Initial startup, resize, FPS changes and runtime codec fallback propagate failure to session-owned cleanup and an actionable Retry row. Late encoder errors from retired generations cannot recreate or fail the replacement pipeline.
3. **Connected indefinitely without video:** the Mac receiver starts a monotonic 15-second first-video deadline. Heartbeats, parameter sets and repeated configuration cannot extend it. A constructed sample submitted to the renderer satisfies it; this is not proof of physical presentation. A static desktop after the first sample is exempt. Timeout reports permission/encoder/log recovery steps, sends the existing `closing` control, cancels that socket within 250 ms and keeps listening.

The reported black-screen incident was subsequently associated with Screen Recording permission. These additional source defects are not evidence that H.264 itself caused that incident. Screen Recording permission is still required.

## Accepted changes and verification

All rows below are implemented in the current source. Pure policy tests and injected failures do not emulate WindowServer or Intel drivers.

| Upstream provenance | Local adaptation | Automated coverage |
| --- | --- | --- |
| `d9eb302d4d25e2c72847420d5e462ff035520e49` | Bounded encoder creation fallback, throwing failure and actual-mode logging through `EncoderSessionFactory`; retains local codec negotiation and hardware requirements. | `EncoderSessionFactorySelfTest`, `SessionLifetimeSelfTest`, stale-callback cases in `StreamEncodingPolicySelfTest`. |
| `c8b24177cbab6df58bfc727873261c53a412cb89` | Replay the latest frame after a 30 ms quiet interval following pre-encode drops. One cached frame and one deadline; busy encode/send budgets defer it. Retirement clears cache and timers. | `CaptureRecoverySelfTest`: last-frame delivery, latest replacement, capacity, cancellation and generations. |
| `ceebb2d46130c8aac912439279d7b1f71c851e31` | Reattach capture to a still-online virtual display while preserving negotiated raster/FPS/codec. Failed reattachment escalates to rebuild after releasing old references. | Recovery policy tests; universal compilation checks production wiring. Actual SCStream recovery remains a hardware check. |
| `09e717edf3ed795869fc8c5a5b094dabb95701d6` | One recovery task/timer; sleep/lock spends no retry budget. Five consecutive awake failed attempts end the session. Only a valid video frame clears failures; duplicate task/delegate failure reports count once. A system Stop while interactive disconnects. | Sleep, retry exhaustion, duplicate failure and user-stop policy cases; session cancellation/cleanup tests. |
| `cde4fc81bbb184baccaef5687ec249be662311b1` | Detect a persistent 1.5-second SCK source-rectangle mismatch, discard cached pixels and reattach. Maximum three source-recovery attempts per session, then an actionable failure. | Mismatch tolerance/reset and recovery-bound tests. |
| `72d4578`, `ad7800d`, geometry from `2a4abf7`, and `1522cd22699b21932d69c718b4afc18bee45d546` | Persist display placement per receiver installation ID; preserve its side when dimensions change. Start the six-second restore window at the first usable tick. OS snapping and failed restores do not overwrite a saved user placement. | `DisplayRecoverySelfTest`: isolated preferences, rotation geometry, delayed ticks, snapping, failed restore and invalid values. |
| `5de42527b8abc08b93ea688798d4efa34dc5db23` | Controller-owned weak participant registry and serial coordinator replace upstream's global registry. Release/recreate only owned virtual displays in unit order; resume live siblings after failure/cancellation. Stop a session on an unowned or persistent collision. Bound registry/waiters to 64, online queries to 256, readiness waits to 2 s and release waits to 3 s. | Collision ownership/order, asynchronous sequential restoration, cancelled lock waiters and sibling recovery on cancellation. |
| `19481a6`, `215100d09477712f75cfd6684a13cc6a68d0edc8` | Aggregate encoder errors at one-second intervals and bound unknown-control logging; retain the existing bounded file writer. | `LogPoliciesSelfTest`, existing `BoundedLogWriterSelfTest`. |
| Local first-video handling | The receiver's 15-second deadline and asynchronous decoder-error checks complement sender failure propagation; no new framing or required control fields. | `MacReceiverFirstVideoSelfTest`: real loopback TCP with heartbeat-only, parameter-only, repeated configuration, valid I/P samples, static desktop, fallback and replacement. |
| `0490441cf147fe8c5f7d13e2f17333aae7544047` | Already covered by independent encode/send budgets. Keep the local two-encode allowance at 60/90/120 FPS and the requested H.264 LAN ceiling of 100 Mbps. | Existing send-budget, bitrate, cursor and receiver-pressure regressions. |

Production review also corrected whole-class MainActor inference: only display-coordination methods require MainActor; video and networking retain their serial queues. Rebuild releases both the retired SCStream and virtual-display references before creating a replacement. Recovery checks console availability after waiting for the coordinator. Generation/task identities protect cancellation, reconnect and stop.

## Other upstream delta

Each of the 18 new main commits was classified. The three Mac fixes above are accepted. The remaining changes do not address this Mac streaming task:

| Commits | Decision |
| --- | --- |
| `195d823`, `6a85e85`, `5aa34ca` | Linux beta and research/planning files: a separate platform, not added by this Mac repair. |
| `f12f6fa`, `6f4b474`, `e2cc20d`, `819e95d`, `839c3ce` | Upstream website, media and beta-download promotion: retain DisplayWeave's existing bilingual website and release claims. |
| `93619ae`, `24ebc6d`, `ed257c7`, `f950547` | Upstream release automation, version and appcasts: retain project release/signing identities and GitHub-only distribution. |
| `501ddb8`, `de3be7d`, `6303fcd` | Upstream Homebrew documentation, issue template and privacy copy: not needed for the capture/encoder repair; no upstream product claims copied. |

Historical 8K-capacity and in-place virtual-display resizing changes are not prerequisites for these recovery ports; the current negotiated resolution/FPS envelope and display identity scheme remain in place. Android protocol, ADB and handover policies are preserved.

## Verification and remaining acceptance

Local evidence is under ignored `build/diagnostics/upstream-review-2026-10-23/`:

- `encoder-before.log`, `first-video-before.log`, `callback-before.log`: failures on the previous creation strategy, heartbeat-only receiver and callback classification.
- `encoder-after.log`, `first-video-after.log`, `lifetime-after.log`: focused fixes pass.
- `swift-tests-expanded.log`: **60 standalone Swift suites pass**, including real receiver TCP/TLS and injected render-pressure cases. Existing standalone CVDisplayLink deprecation warnings remain.
- `mac-build-expanded-cleanup.log`: unsigned Debug Mac build passes for **arm64 and x86_64**, with no warnings or errors. Xcode project generated from `project.yml`.
- `receiver-window-compile.log`, `virtual-display-compile.log`: both interactive fixtures compile with their updated source dependencies; neither binary was run.
- Bilingual documentation (95 pairs), release-link checks and `git diff --check` pass. The new guide pairs are registered in the documentation gate.

During this source-audit round, no app was installed, launched, signed or released. Subsequent packaging and release checks are recorded in [v0.3.0 notes](../releases/release-notes-v0.3.0.md). No screen capture, receiver window, virtual-display creation or WindowServer restart was used. **SKIP:** Intel/macOS 15 runtime, two-Mac Ethernet presentation/latency, actual sleep/wake, multiple virtual displays and sustained 4K60. The local host is arm64/macOS 26.5.2. Automated policies and a universal build cannot prove those hardware behaviors.

After packaging, a brief normal 4K workload check and one pair of logs can check selected encoder mode, first video, actual transport and capture/encode/send rates. Multi-display recovery additionally needs a deliberate sleep/wake/rebuild check on suitable hardware; it is not a claim made by the synthetic tests.

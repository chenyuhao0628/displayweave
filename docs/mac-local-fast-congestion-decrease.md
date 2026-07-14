[English](mac-local-fast-congestion-decrease.md) | [简体中文](mac-local-fast-congestion-decrease.zh-CN.md)

# Mac local fast congestion decrease

## Modified files

- `Mac/AdaptiveBitrateController.swift`: local 200 ms input, shared hold/state, and unified decision identity;
- `Mac/MacSender.swift`: pending-send age/completion tracking, local sampling, and serialized encoder-output state;
- `Mac/BenchmarkSample.swift`: local metrics and decision evidence in CSV/JSONL;
- standalone tests and bilingual documentation/indexes.

## Purpose

PR 8 adds a bounded Mac-local congestion path so an already-growing send queue does not need to wait for the roughly one-second receiver-stat loop. It preserves that receiver loop for RTT, Frame Age, Android queue/drop evidence, and slow recovery.

The new path is active only in Auto bitrate mode. It can decrease bitrate but can never increase it.

## Local sampling and state

The sender samples every 200 ms (within the requested 100–250 ms range) and records:

- `pendingSends` and the configured queue budget;
- age of the oldest current pending send;
- local encoded and successfully sent FPS for the sample;
- the latest send-completion delay.

Each send owns a monotonic start timestamp and identity. A completion removes only its own identity; a late completion from a cleared/replaced connection cannot decrement a newer connection's pending count. VideoToolbox output handling is serialized onto the sender queue before it mutates these metrics.

## Decision policy

A local sample is congested when either:

- `pendingSends >= queueBudget`; or
- at least one send is pending and the oldest pending age grows by more than 1 ms from the previous sample.

Two consecutive congested samples are required. The fast path then lowers the current target by 12%, clamped to the existing codec/transport bounds. It resets its consecutive counter after a decision and never performs an increase.

The local and receiver paths use the same controller and expose:

- `localFastDecrease`;
- `receiverCongestionDecrease`;
- `stableRecoveryIncrease`;
- `decisionEpoch`, `lastDecreaseReason`, and monotonic `lastDecreaseAt`.

All decreases share the existing one-second decrease hold. Therefore a receiver-stat sample cannot lower bitrate again immediately after a local decrease for the same congestion episode. Stable recovery still requires the existing five-second healthy window and increase cooldown.

## Tests

- failure-first controller tests cover two-sample queue confirmation, 12% bounded decrease, two rising-age samples, Auto-only behavior, and the decrease-only invariant;
- shared-state tests prove a receiver decision cannot double-decrease inside the hold and verify decision epoch/reason/time;
- Benchmark tests cover source, trigger, epoch, last-decrease state, local queue age, completion delay, and stable/unique CSV columns;
- the macOS target build exercises the real sender integration and serialized encoder callback path.

## Build result

- Focused controller and Benchmark standalone tests: passed.
- Android clean test/Debug build: `61 actionable tasks: 61 executed`; all six Android self-test groups passed.
- All 21 Mac standalone self-tests passed.
- `xcodegen generate` completed successfully.
- macOS Debug and generic iOS Simulator Debug builds with signing disabled: `BUILD SUCCEEDED`.
- Production website build and prerender passed; bilingual documentation check passed for 31 pairs; release-link and `git diff --check` checks passed.
- `adb devices -l` reported no attached device, so no physical result is claimed.

## Before/after metrics

No physical congestion A/B has been collected. This PR does not claim faster recovery or lower Frame Age; it adds a measurable, bounded response path and records the evidence needed to evaluate it.

## Known risks

- A full send queue may reflect a short scheduler stall rather than sustained network congestion; two-sample confirmation limits but does not eliminate false positives.
- The 12% step and 200 ms interval are initial bounded values and require same-condition validation.
- Send-completion delay is recorded but is not an independent trigger in this first policy; queue occupancy and oldest-age growth make the decision.
- Repeated long congestion can still produce later decreases after the shared hold expires; PR 8 prevents immediate duplicate reaction, not all multi-step convergence.

## Pending physical validation

- induce controlled WiFi and ADB USB backpressure and verify the first local decision occurs after two 200 ms samples;
- confirm the next receiver window does not duplicate the local decrease inside the shared hold;
- compare target/actual bitrate, oldest pending age, completion delay, sent/encoded FPS, Frame Age P50/P95/P99, and rendered FPS;
- verify Manual and Benchmark modes never change target bitrate through the local path;
- repeat reconnect and transport-switch checks to confirm late completions do not alter the new connection's queue.

No physical receiver was attached during implementation.

## Next step

PR 9 should design/test the negotiated Android binary frame header and reduce repeated NAL scans/per-frame allocation without changing Legacy iOS framing.

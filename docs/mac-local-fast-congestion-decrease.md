[English](mac-local-fast-congestion-decrease.md) | [简体中文](mac-local-fast-congestion-decrease.zh-CN.md)

# Mac local congestion and recovery

This guide describes the 2026-10-26 source iteration, not a new published release. PR 8 introduced the local decrease path; subsequent work added Mac receiver recovery. Current implementation and verification are recorded in the [upgrade ledger](reliability-experience-upgrade.md).

## Sampling and ownership

In Auto mode, the sender samples pending-send count/budget, oldest send age, encoded/sent FPS and completion delay every 200 ms. Each send owns its monotonic timestamp and identity. A completion removes only its own entry; a late completion from an old connection cannot decrement the replacement connection's count. Encoder output handling is serialized on the sender queue.

Two consecutive samples at the send budget, or with a pending send whose oldest age grows by more than 1 ms, lower the target by 12% within codec/transport bounds. Local and receiver decreases share a one-second hold and decision epoch. Receiver pressure can separately lower the target by 20%; it cannot immediately duplicate a local decrease inside that hold. Manual and Benchmark never adapt.

## Recovery

Mac receivers do not send the mobile `stats` message. Their local recovery accepts active queues below the configured budget when oldest age and completion delay are each at most `max(8 ms, one encoded-frame interval)`, and successfully sent FPS is at least 95% of encoded FPS. A nonzero queue alone no longer blocks restoration. Missing samples for more than one second reset the healthy interval.

After three healthy seconds, the target rises 20%, with a default three-second increase cooldown. It never exceeds the original Auto target without receiver measurements. For mobile receivers, restoration below the initial target follows the same 20% / 3-second policy; probing above it remains 7% / 5 seconds. Actual receiver sampling can extend those intervals.

Mac capture skips and encoder output drops are diagnostic; they do not independently imply network congestion. Local queue/age pressure and receiver-specific signals still do. See [adaptive bitrate](adaptive-bitrate.md).

## Verification and limits

Production controller regressions cover queue/age confirmation, bounded decreases, shared hold, late/invalid samples, healthy active queue recovery, Manual/Benchmark stability, and the original-target ceiling. Synthetic receiver-driven recovery from 8 to 40 Mbps completes within 38 seconds. This is policy execution, not a measured network result. Benchmark serialization retains the decision source/trigger/epoch, queue age and completion delay.

A full queue can still reflect scheduler pressure, and two-sample confirmation cannot eliminate all false positives. The 12% decrease, 200 ms sampling and recovery thresholds require physical A/B validation. Compare target/actual bitrate, send age, frame-age p50/p95/p99, rendered FPS, visual clarity and oscillation under the same scene. Include reconnect and transport changes to verify ownership. Physical LAN/USB congestion and endurance evidence remain pending.

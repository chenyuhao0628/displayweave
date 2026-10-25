[English](adaptive-bitrate.md) | [简体中文](adaptive-bitrate.zh-CN.md)

# Adaptive bitrate

DisplayWeave exposes Auto, Manual, and Benchmark bitrate modes. Auto starts from the resolution/FPS/codec estimate, clamped to codec and transport bounds. Manual uses a bounded preset. Benchmark permits 10–200 Mbps and is experimental.

Only Auto adapts. In the current source iteration (2026-10-26, not yet released), congestion reduces the target by 20% after the one-second decrease hold. Below the initial target, three healthy seconds permit a 20% increase up to that target; above it, probing remains 7% per five healthy seconds. The default independent increase cooldown is three seconds. Receiver sampling can extend those intervals. LAN signals include pending sends, repeated Android queue depth, send deficit, rising frame age, rising RTT, and two consecutive windows of classified Android decoder-throughput drops. Mac capture/encoder drops remain diagnostic and do not independently lower bitrate or block recovery. USB uses stricter link attribution: capture skips, mismatched FPS windows, and short RTT or frame-age changes do not lower bitrate by themselves; real pending sends and Android decoder pressure remain effective. Lifecycle, stale-identity, malformed-input, transport, and codec-reconfiguration drops do not lower bitrate or block stable recovery. Legacy aggregate Android drops are retained for observation but are not guessed to be congestion. Manual and Benchmark never adapt. See the [Android drop-reason policy](android-drop-reason-policy.md).

Runtime changes update VideoToolbox `AverageBitRate` and `DataRateLimits`, then send a new `streamConfig`; they do not rebuild the encoder. Logs and benchmark rows keep target and actual bitrate separate and record previous target, new target, reason, and network state.

The Mac also samples local send pressure every 200 ms. Two consecutive full-queue or rising-oldest-age samples can issue a bounded 12% `localFastDecrease`. Local, receiver, and stable-recovery decisions share one decrease hold and decision epoch; see [local fast congestion decrease](mac-local-fast-congestion-decrease.md).

The controller and serialization paths have automated coverage. Physical congestion/recovery testing is still required before treating the thresholds as final.

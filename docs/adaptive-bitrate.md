# Adaptive bitrate

DisplayWeave exposes Auto, Manual, and Benchmark bitrate modes. Auto starts from the resolution/FPS/codec estimate, clamped to codec and transport bounds. Manual uses a bounded preset. Benchmark permits 10–200 Mbps and is experimental.

Auto evaluates receiver statistics only. Congestion reduces the target by 20% after the one-second decrease hold. Five stable seconds permit a 7% increase, with an independent five-second increase cooldown. Signals include pending sends, Mac drops, repeated Android queue depth, send deficit, rising frame age, rising RTT, and two consecutive windows of classified Android decoder-throughput drops. Lifecycle, stale-identity, malformed-input, transport, and codec-reconfiguration drops do not lower bitrate or block stable recovery. Legacy aggregate Android drops are retained for observation but are not guessed to be congestion. Manual and Benchmark never adapt. See the [Android drop-reason policy](android-drop-reason-policy.md).

Runtime changes update VideoToolbox `AverageBitRate` and `DataRateLimits`, then send a new `streamConfig`; they do not rebuild the encoder. Logs and benchmark rows keep target and actual bitrate separate and record previous target, new target, reason, and network state.

The Mac also samples local send pressure every 200 ms. Two consecutive full-queue or rising-oldest-age samples can issue a bounded 12% `localFastDecrease`. Local, receiver, and stable-recovery decisions share one decrease hold and decision epoch; see [local fast congestion decrease](mac-local-fast-congestion-decrease.md).

The controller and serialization paths have automated coverage. Physical congestion/recovery testing is still required before treating the thresholds as final.

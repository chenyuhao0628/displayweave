# Adaptive bitrate

DisplayWeave exposes Auto, Manual, and Benchmark bitrate modes. Auto starts from the resolution/FPS/codec estimate, clamped to codec and transport bounds. Manual uses a bounded preset. Benchmark permits 10–200 Mbps and is experimental.

Auto evaluates receiver statistics only. Congestion reduces the target by 20% after the one-second decrease hold. Five stable seconds permit a 7% increase, with an independent five-second increase cooldown. Signals include pending sends, Mac/Android drops, repeated Android queue depth, send deficit, rising frame age, and rising RTT. Manual and Benchmark never adapt.

Runtime changes update VideoToolbox `AverageBitRate` and `DataRateLimits`, then send a new `streamConfig`; they do not rebuild the encoder. Logs and benchmark rows keep target and actual bitrate separate and record previous target, new target, reason, and network state.

The controller and serialization paths have automated coverage. Physical congestion/recovery testing is still required before treating the thresholds as final.

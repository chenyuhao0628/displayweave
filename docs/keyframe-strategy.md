# Keyframe strategy

The candidate periodic GOP is two seconds on WiFi and one second on USB. This reduces periodic WiFi bursts while retaining faster wired recovery.

## Reason policy

Dropping a raw ScreenCaptureKit frame before it enters VideoToolbox does not
alter the encoded reference chain, so `preEncodeCaptureSkip` increments the
drop counters without forcing an IDR. A stale-session frame is also ignored
without an IDR. The following recovery causes still force the next encoded
frame to be a keyframe:

- encoded-frame discard;
- transport write failure;
- receiver keyframe request or decoder reset;
- reconnect;
- codec fallback; and
- encoder or stream reconfiguration.

Repeated receiver requests arriving before the forced frame finishes encoding
are coalesced into one IDR. A reconnect, decoder reset, codec fallback, or
stream reconfiguration supersedes an in-flight request because the older frame
may belong to an invalid configuration; it schedules one new pending IDR.
Total requests and coalesced requests continue to be counted by reason. This
changes neither the legacy iOS framing nor Android Protocol V2 negotiation.

Debug and Benchmark records include keyframe request reason, request count,
coalesced count, observed keyframe count, average keyframe size, peak frame
size, queue depth, and nearby Frame Age P95 when available. Physical tests must
compare WiFi GOPs of 1/2/3 seconds and USB GOPs of 1/2 seconds, including queue
and frame-age spikes plus decoder recovery time.

The selected defaults are provisional until those tests are recorded.

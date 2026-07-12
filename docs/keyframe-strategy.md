# Keyframe strategy

The candidate periodic GOP is two seconds on WiFi and one second on USB. This reduces periodic WiFi bursts while retaining faster wired recovery. Immediate keyframes remain enabled for receiver requests, reconnects, codec failures/fallback, queue drops, and encoder/stream reconfiguration.

Debug encoder statistics report keyframe count, average keyframe size, peak frame size, and queue depth at the end of each window. Physical tests must compare WiFi GOPs of 1/2/3 seconds and USB GOPs of 1/2 seconds, including queue and frame-age spikes plus decoder recovery time.

The selected defaults are provisional until those tests are recorded.

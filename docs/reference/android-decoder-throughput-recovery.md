[简体中文](android-decoder-throughput-recovery.zh-CN.md) | English

# Android Decoder Throughput and Recovery

This change prevents a high-refresh Android stream from turning temporary
encoder or decoder pressure into seconds of stale video and reference-frame
corruption.

## Sender Backpressure

The Mac pipeline budget now counts both VideoToolbox encodes and Network.framework
sends. Previously it counted sends only, so an asynchronous encoder could accept
many frames while the socket appeared empty and later emit a large stale burst.
High, Balanced/Low, and Gaming retain budgets of 3, 2, and 1 respectively, but
the budget now covers the whole encode-to-send pipeline.

## Decoder Capability and Scheduling

Android caps the advertised `maxFps` using the preferred hardware decoder's
`VideoCapabilities`. Published performance points are preferred; devices without
them fall back to `areSizeAndRateSupported`. The display refresh rate is still an
upper bound, not a decoder performance claim.

MediaCodec input and output now use asynchronous callbacks. One latest pending
input frame is retained until a codec input buffer becomes available, replacing
the previous zero-timeout `dequeueInputBuffer(0)` polling behavior.

## Reference Safety

If an already encoded inter-frame is replaced before decode, the receiver marks
the reference chain broken, requests a keyframe, and rejects dependent frames
until a keyframe arrives. The non-congestion drop reason is
`referenceChainBroken`; it must not be interpreted as network congestion by the
adaptive bitrate controller.

## Surface Refresh Mapping

When an exact display mode is unavailable, Surface frame-rate selection now
chooses the smallest supported rate at or above the stream FPS. It only falls
back below the requested FPS when no higher mode exists. A 90 FPS stream on a
60/120/165 Hz device therefore requests 120 Hz instead of 60 Hz.

## Validation

- Android policy, protocol, lifecycle, connection, and update self-tests pass.
- Android Debug APK assembly passes.
- Mac send-queue policy self-test covers combined encode/send pressure.

Physical validation must still compare 60/90/120 FPS on the same device and
scene. Required evidence includes pending encodes/sends, actual send/receive/
decode/render FPS, frame-age percentiles, `referenceChainBroken`, keyframe
requests, and visual stability.

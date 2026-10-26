[English](low-latency-queue-analysis.md) | [简体中文](low-latency-queue-analysis.zh-CN.md)

# Low-latency send queue analysis

The sender already enables TCP no-delay and accounts for an outstanding send until Network.framework reports completion. It drops a newly captured frame when the outstanding-send count reaches the budget, preventing an extra frame from entering the queue.

Candidate budgets are Gaming 1, Low/Balanced 2, and High 3. Because this drop happens before encoding, it does not break the encoded reference chain and no longer requests a keyframe. Encoded-frame loss, transport write failure, reconnect, decoder recovery, codec fallback, and stream reconfiguration still request one. These values are policy defaults with unit coverage, not physical A/B conclusions.

The v0.3.1 release (2026-10-26) retains Android’s two 12-frame FIFO capacities but gives each packet one **150 ms receive-to-codec deadline**. A retained buffer keeps its original monotonic timestamp across both queues. Admission and actual codec submission reject expired packets, clear dependent pending frames, and request a fresh keyframe. The bound does not include network time before receipt or presentation after codec submission, so it is not an end-to-end latency claim. The threshold needs physical scheduler/decoder A/B evidence; it is covered by expiration and reference-chain regressions.

Validation must compare average FPS, 1% low FPS, frame age, estimated end-to-end latency, drops, keyframe requests, and visual stability on the same scene. Accept only a budget whose queue stays near zero without excessive drops or keyframe churn.

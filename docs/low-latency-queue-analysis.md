# Low-latency send queue analysis

The sender already enables TCP no-delay and accounts for an outstanding send until Network.framework reports completion. It drops a newly captured frame when the outstanding-send count reaches the budget, preventing an extra frame from entering the queue.

Candidate budgets are Gaming 1, Low/Balanced 2, and High 3. Because this drop happens before encoding, it does not break the encoded reference chain and no longer requests a keyframe. Encoded-frame loss, transport write failure, reconnect, decoder recovery, codec fallback, and stream reconfiguration still request one. These values are policy defaults with unit coverage, not physical A/B conclusions.

Validation must compare average FPS, 1% low FPS, frame age, estimated end-to-end latency, drops, keyframe requests, and visual stability on the same scene. Accept only a budget whose queue stays near zero without excessive drops or keyframe churn.

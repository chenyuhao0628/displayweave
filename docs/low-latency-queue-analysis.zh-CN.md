[English](low-latency-queue-analysis.md) | [简体中文](low-latency-queue-analysis.zh-CN.md)

# 低延迟发送队列分析

发送端已启用 TCP no-delay，并持续占用 pending 计数直到 Network.framework 回报发送完成。当前待发送数达到预算时会丢弃新捕获帧，避免再多塞入一帧。

候选预算为 Gaming 1、Low/Balanced 2、High 3。这里的 Drop 发生在编码前，不会破坏已经编码的参考链，因此不再请求关键帧；已编码帧丢失、Transport Write 失败、重连、Decoder Recovery、Codec Fallback 与 Stream Reconfigure 仍会请求关键帧。这些数值是有单元测试覆盖的候选默认值，不是实体 A/B 结论。

v0.3.1（2026-10-26）保留 Android 两级各 12 帧的 FIFO 容量，同时让每帧共享一个 **150 ms 接收到提交解码器的期限**。保留缓冲区所有权时仍沿用原始单调时钟时间戳，跨队列不重置。解码入口与实际提交处拒绝超时帧，清理依赖它的待处理帧并请求新关键帧。此期限不包括接收前网络耗时或解码提交后的呈现，不代表端到端延迟。已覆盖过期和参考链回归；阈值仍需实体调度／解码 A/B 证据。

实体验证必须在同场景比较平均 FPS、1% Low FPS、Frame Age、估算 E2E 延迟、丢帧、关键帧请求和视觉稳定性。只有队列接近零且不造成过多丢帧或关键帧抖动的预算才能接受。

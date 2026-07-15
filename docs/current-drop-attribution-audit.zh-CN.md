[English](current-drop-attribution-audit.md) | [简体中文](current-drop-attribution-audit.zh-CN.md)

# 当前 Drop 归因审计

基线：`79cbf90`；真机验证：**Pending**。

- `REFERENCE_CHAIN_BROKEN` 正确标记为非拥塞：它是恢复状态，不是直接网络压力证据。
- `LATEST_SLOT_REPLACED` 与 `DECODER_INPUT_UNAVAILABLE` 属于拥塞相关，但 ABR 将持续接收端证据标为 `android-decoder-throughput`，不能描述成已证明的网络拥塞。
- `IMPORTANT_FRAME_PROTECTED` 发生于 Latest Slot 占用压力。被丢弃的 Incoming Frame 为预测帧时，服务端/Decoder 现在会进入参考链恢复、合并关键帧请求，并在新关键帧到达前拒绝依赖帧；仅保留较早的重要帧并不能证明后续预测帧安全。
- Stale Generation/Session/Config、Malformed、Oversize、Surface Loss、Reconfigure 与 Transport Failure 均不进入 ABR 拥塞计数。
- Transport Read/Write Failure 只记录一个 Drop；后续 Disconnect 不再增加 Drop。
- Latest Slot Replacement 后再记录 Reference Chain Break 对应两个不同被丢帧，不是同帧双计数。
- Window Count 发布后清零，Total 保留；Last Event 随窗口重置，且只在 Current Generation 检查后接收。

真实 Decoder/Network 负载与各类 Drop 的相关性仍为 Pending。恢复频率应单列，用作限制 FPS/分辨率的证据，而不能直接等价为降码率理由。

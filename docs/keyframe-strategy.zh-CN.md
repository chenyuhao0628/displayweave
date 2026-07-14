# 关键帧策略

周期 GOP 候选默认值为 WiFi 两秒、USB 一秒：减少 WiFi 周期性突发，同时保留有线连接的快速恢复。

## 原因策略

ScreenCaptureKit 原始帧在进入 VideoToolbox 前被丢弃，不会改变已经编码的参考链，
因此 `preEncodeCaptureSkip` 只增加 Drop 计数，不再强制 IDR。旧 Session Frame
同样不会请求 IDR。以下恢复原因仍会强制下一编码帧成为关键帧：

- 已编码 Frame 被丢弃；
- Transport Write 失败；
- Receiver Keyframe Request 或 Decoder Reset；
- Reconnect；
- Codec Fallback；
- Encoder 或 Stream Reconfigure。

强制帧完成 Encode 前重复到达的 Receiver Request 会合并成一个 IDR。Reconnect、
Decoder Reset、Codec Fallback 或 Stream Reconfigure 会替换 In-flight Request，
因为旧 Frame 可能属于已失效的 Config；此时只安排一个新的 Pending IDR。同时
继续按原因累计总请求数与合并数。此修改不改变 Legacy iOS Framing，也不改变
Android Protocol V2 协商。

Debug 与 Benchmark 记录会在可用时包含 Keyframe Request Reason、Request Count、
Coalesced Count、实测 Keyframe Count、平均 Keyframe Size、Peak Frame Size、Queue
Depth 和附近的 Frame Age P95。实体测试必须比较 WiFi 1/2/3 秒与 USB 1/2 秒 GOP，
同时观察 Queue/Frame Age 峰值和 Decoder Recovery Time。

完成并记录这些测试前，当前默认值仍属于候选值。

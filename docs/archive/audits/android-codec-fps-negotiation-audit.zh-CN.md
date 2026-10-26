[English](android-codec-fps-negotiation-audit.md) | [简体中文](android-codec-fps-negotiation-audit.zh-CN.md)

> 历史记录：保留撰写时的版本、命令和结论，不作为当前操作指南。当前入口见[文档导航](../../README.zh-CN.md)。

# Android Codec/FPS 协商审计

基线：`79cbf90`；真机验证：**Pending**。

- **FPS-001（P1，本地已修）：**原广告上限未绑定运行时候选顺序。现使用与默认 Decoder Policy 相同的硬件加速/Low Latency 排序，并评估具名选中候选，而非在原始枚举中提前返回。
- **FPS-002（P1，本地保守修复）：**原 Codec 回退不保持能力上限。HEVC 为首选时，广告最大 FPS 现取所选 HEVC 与所选 H.264 回退候选共同支持的较小值，回退后不会保留 HEVC-only 承诺。
- **FPS-003（已实现；实机矩阵待完成）：**`DecoderRuntimeInfo` 与 `decoderConfigured` 已上报选中 decoder/max FPS。`MacSender.applySelectedDecoderFpsCap` 只降低运行档位并重发配置，不向上振荡。厂商能力和旋转仍需设备证据，见[运行时恢复](../../reference/android-decoder-throughput-recovery.zh-CN.md)。
- 宽高：广告尺寸来自当前 Window Bounds，经 Display Profile 缩放并做偶数对齐；方向变化会重算 DisplaySpec，真机旋转仍为 Pending。
- 刷新映射：选择不低于请求 Bucket 的最小有效模式；测试覆盖 90→120、120→165，59.94 归为 60。Surface Request 与实际 Display Hz 保持不同指标。

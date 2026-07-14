[English](android-codec-fps-negotiation-audit.md) | [简体中文](android-codec-fps-negotiation-audit.zh-CN.md)

# Android Codec/FPS 协商审计

基线：`79cbf90`；真机验证：**Pending**。

- **FPS-001（P1，本地已修）：**原广告上限未绑定运行时候选顺序。现使用与默认 Decoder Policy 相同的硬件加速/Low Latency 排序，并评估具名选中候选，而非在原始枚举中提前返回。
- **FPS-002（P1，本地保守修复）：**原 Codec 回退不保持能力上限。HEVC 为首选时，广告最大 FPS 现取所选 HEVC 与所选 H.264 回退候选共同支持的较小值，回退后不会保留 HEVC-only 承诺。
- **FPS-003（P2，真机 Pending）：**厂商能力误报仍需要运行时反馈。Configure/Runtime Failure 可能越过静态首选候选；配置后已有实际 Decoder Name，但尚未发布 Selected Decoder Max FPS 或运行时 FPS 降级握手。
- 宽高：广告尺寸来自当前 Window Bounds，经 Display Profile 缩放并做偶数对齐；方向变化会重算 DisplaySpec，真机旋转仍为 Pending。
- 刷新映射：选择不低于请求 Bucket 的最小有效模式；测试覆盖 90→120、120→165，59.94 归为 60。Surface Request 与实际 Display Hz 保持不同指标。

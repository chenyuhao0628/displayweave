[English](current-remediation-plan.md) | [简体中文](current-remediation-plan.zh-CN.md)

# 当前补正计划

静态补正已在本地工作区完成。发布时建议维持以下审查边界：

1. **PR A——异步 MediaCodec 所有权与旧 Callback 安全：**Decoder Generation 门控、严格 Input Index 所有权、有界 Rendered Telemetry、合并的终止错误恢复，以及确定性 Callback State 测试。
2. **PR B——参考链正确性：**识别 HEVC IRAP/CRA，并确定性覆盖等待关键帧与恢复流程。
3. **PR C——Codec/FPS 能力协商：**广告上限绑定默认运行时候选排序；HEVC 首选上限同时受所选 H.264 回退路径的共同能力约束。
4. **PR D——Mac Generation 化工作计数：**由 Encoder Generation 拥有 Work，并记录 Peak 与未匹配 Completion。在实测 A/B 证据支持前保持现有预算不变。
5. **PR E——指标、CI、发布与文档：**可复位的 GC 窗口增量、权威 Swift Self-test Runner、CI Gate、双语审计以及 Release/Feed 验证。

剩余验证全部依赖硬件：设备具备后执行已记录的 WiFi/USB、Codec、刷新率、恢复与 Legacy 矩阵。在此之前，相关结论全部保持 **Pending**。Buffer Pool 仍只做设计；在通过测量证明 Buffer 生命周期与所有权之前不实施。

每个 PR 都必须保持 Legacy 输出逐字节一致，也不得把源码测试结果表述为真机性能结论。

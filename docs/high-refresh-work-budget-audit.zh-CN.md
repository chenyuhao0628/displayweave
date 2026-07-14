[English](high-refresh-work-budget-audit.md) | [简体中文](high-refresh-work-budget-audit.zh-CN.md)

# 高刷新工作预算审计

基线：`79cbf90`；真机 A/B：**Pending**。

`SendQueuePolicy` 使用 `max(pendingSends, 0) + max(pendingEncodes, 0)` 与质量预算比较（Gaming 1、Low/Balanced 2、High 3）。Drop 位于 Encode 前且不强制关键帧，因此不会破坏已编码参考链。

- **WB-001（P1）：Encode 所有权未按 Generation 隔离。** `pendingEncodes` 是单一标量。Callback 虽携带 `wireConnectionGeneration` 拒绝发送旧帧，但在校验 Generation 前先减少共享计数。重连清除 Pending Send，却不清除 Pending Encode。延迟或缺失回调会占用新会话预算；若未来直接清零，则旧回调又会减少新会话工作。应改为按 Encoder/Wire Generation 计数。
- **WB-002（P2）：缺少 Peak 和不变量指标。** 当前用 `max(0, ...)` 隐藏潜在下溢，应增加 Peak、未匹配 Completion 计数和 Debug 断言。
- **WB-003（P2）：本地快速下降仅使用 Queue-at-budget 与 Oldest-age-rising。** `encodedFps`、`sentFps`、`sendCompletionDelayMs` 只被校验和观测，不参与控制。本轮不在缺少真机 A/B 时草率改变条件。
- **WB-004（P2）：预算最优值未验证。** 静态源码不能证明 60/90/120fps 下不会过度 Drop，默认值保持不变并标记待真机受控测试。

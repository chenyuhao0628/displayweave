[English](mac-local-fast-congestion-decrease.md) | [简体中文](mac-local-fast-congestion-decrease.zh-CN.md)

# Mac 本地快速拥塞下降

## Modified Files

- `Mac/AdaptiveBitrateController.swift`：本地 200 ms 输入、共享 Hold/State 与统一 Decision Identity；
- `Mac/MacSender.swift`：Pending-send Age/Completion 跟踪、本地采样及串行化 Encoder-output State；
- `Mac/BenchmarkSample.swift`：CSV/JSONL 中的本地指标与决策证据；
- Standalone Test 和双语文档/索引。

## Purpose

PR 8 增加有界的 Mac 本地拥塞通道，使已经增长的发送队列无需等待约一秒一次的 Receiver-stat Loop。Receiver Loop 继续负责 RTT、Frame Age、Android Queue/Drop 证据与慢速恢复。

新通道仅在 Auto Bitrate 模式启用，只能降码率，永远不能升码率。

## Local Sampling and State

Sender 每 200 ms 采样一次（位于要求的 100～250 ms 范围），记录：

- `pendingSends` 与配置的 Queue Budget；
- 当前最老 Pending Send 的 Age；
- 该采样窗口的本地 Encoded FPS 与成功 Sent FPS；
- 最近一次 Send-completion Delay。

每次 Send 拥有 Monotonic Start Timestamp 与 Identity。Completion 只能移除自己的 Identity；已清理/替换连接的晚到 Completion 不能减少新连接的 Pending Count。VideoToolbox Output 会先串行投递到 Sender Queue，再修改这些指标。

## Decision Policy

满足任一条件的本地样本视为 Congested：

- `pendingSends >= queueBudget`；或
- 至少有一个 Pending Send，且最老 Pending Age 相比前一采样增长超过 1 ms。

必须连续两个 Congested Sample。随后 Fast Path 把当前 Target 降低 12%，并受既有 Codec/Transport Bound 约束。决策后重置连续计数，且绝不执行 Increase。

Local 与 Receiver Path 使用同一个 Controller，并发布：

- `localFastDecrease`；
- `receiverCongestionDecrease`；
- `stableRecoveryIncrease`；
- `decisionEpoch`、`lastDecreaseReason` 与 Monotonic `lastDecreaseAt`。

所有 Decrease 共享既有一秒 Decrease Hold，因此同一拥塞事件的 Local Decrease 之后，Receiver-stat Sample 不能立即再次降低。Stable Recovery 继续要求既有五秒 Healthy Window 与 Increase Cooldown。

## Tests

- Failure-first Controller Test 覆盖 Queue 双样本确认、12% 有界下降、Age 连续增长双样本、仅 Auto 启用及只降不升不变量；
- Shared-state Test 证明 Receiver Decision 不能在 Hold 内重复下降，并核对 Decision Epoch/Reason/Time；
- Benchmark Test 覆盖 Source、Trigger、Epoch、Last-decrease State、本地 Queue Age、Completion Delay 与稳定且唯一的 CSV Column；
- macOS Target Build 覆盖真实 Sender Integration 与串行化 Encoder Callback Path。

## Build Result

- 聚焦 Controller 与 Benchmark Standalone Test：通过；
- Android Clean Test/Debug Build：`61 actionable tasks: 61 executed`，六组 Android Self Test 全部通过；
- 全部 21 个 Mac Standalone Self Test 通过；
- `xcodegen generate` 成功完成；
- 关闭签名的 macOS Debug 与通用 iOS Simulator Debug Build：`BUILD SUCCEEDED`；
- Production Website Build/Prerender、31 对双语文档检查、Release-link Check 与 `git diff --check` 全部通过；
- `adb devices -l` 未发现已连接设备，因此不声称获得真机结果。

## Before/After Metrics

尚未采集真机拥塞 A/B。本 PR 不声称恢复更快或 Frame Age 更低，只增加可测量、有边界的响应路径，并记录评估所需证据。

## Known Risks

- 满 Send Queue 可能来自短时 Scheduler Stall 而非持续网络拥塞；双样本确认只能降低、不能消除误判；
- 12% Step 与 200 ms Interval 是初始有界值，仍需同条件验证；
- Send-completion Delay 会记录，但第一版不把它作为独立 Trigger；决策使用 Queue Occupancy 与 Oldest-age Growth；
- 长时间拥塞在 Shared Hold 到期后仍可继续多步下降；PR 8 防止立即重复反应，而不是禁止所有逐步收敛。

## Pending Physical Validation

- 制造受控 WiFi 与 ADB USB Backpressure，确认第一次本地决策发生在两个 200 ms Sample 后；
- 确认下一 Receiver Window 不会在 Shared Hold 内重复本地下降；
- 比较 Target/Actual Bitrate、Oldest Pending Age、Completion Delay、Sent/Encoded FPS、Frame Age P50/P95/P99 与 Rendered FPS；
- 验证 Manual 与 Benchmark 模式不会通过本地通道改变 Target Bitrate；
- 重复 Reconnect 与 Transport-switch，确认晚到 Completion 不会改变新连接 Queue。

实现期间没有连接实体 Receiver。

## Next Step

PR 9 应设计/测试协商式 Android Binary Frame Header，并减少重复 NAL Scan/Per-frame Allocation，同时不改变 Legacy iOS Framing。

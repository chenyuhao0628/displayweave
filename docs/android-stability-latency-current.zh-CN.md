[English](android-stability-latency-current.md) | [简体中文](android-stability-latency-current.zh-CN.md)

# Android 稳定性与延迟——当前状态

当前代码基线：`79cbf90` 加 `current-code-audit-report.zh-CN.md` 记录的本地审计补正。实现前的历史表格保留在[基线审计](android-stability-latency-audit.zh-CN.md)。

| 领域 | 当前状态 | 证据 | 真机验证 |
| --- | --- | --- | --- |
| Connection Generation / 独立 Accept Loop | 已实现 | 不可变 Transport Context、Current Generation Coordinator、接管自测试 | Pending |
| Session Epoch / Config Version / Frame Sequence | 协商 V2 已实现；保留 Legacy | Protocol Session 过滤与自测试 | Pending |
| StreamConfig Ack / Decoder Ready / First Frame Rendered | V2 已实现 | 类型化消息与身份检查 | Pending |
| Frame Size 协商 | 已实现：Legacy 1 MiB、V2 默认 8 MiB、绝对 16 MiB | Protocol 测试与 Transport Loopback | Pending |
| 异步 MediaCodec | 已实现；本地补正 Callback Generation、Input 所有权、有界 Telemetry 和终止恢复 | 确定性状态测试；Android 构建通过 | Pending |
| 参考链恢复 | H.264 IDR、HEVC IRAP 16–23 已实现；断链后拒绝依赖帧 | 分类器及状态自测试 | Pending |
| Decoder Low Latency / WiFi Lock / Surface Frame Rate | 已实现模式、生命周期和指标 | Policy/Lifecycle 测试 | Pending |
| Drop 归因 / ABR 过滤 | 已实现；恢复 Drop 不计为拥塞 | Drop Tracker 与 ABR 测试 | Pending |
| Mac Combined Work Budget | 已实现；本地增加 Encoder Generation 所有权 | SendQueue/Generation 测试；macOS 构建通过 | 60/90/120 A/B Pending |
| Binary Frame Header V2 | 仅完整能力协商后启用 | 畸形输入、能力门控、Legacy 逐字节测试 | 协议已验证；运行 Pending |
| Thermal/Power 与 Allocation/GC | 已实现；GC 字段现为窗口增量 | 指标自测试 | 相关性 Pending |
| Frame Buffer Pool | 按设计未实现 | 只有所有权设计 | 不适用 |

没有 `current-physical-validation-matrix.zh-CN.md` 中的真机证据，不声称性能、恢复时间或兼容结果。

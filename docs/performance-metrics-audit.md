# DisplayWeave 性能指标覆盖审计

审计日期：2026-07-11
依据：`DisplayWeave 下一阶段优化计划（低延迟 + 高刷新率 + 高码率）V1.0`

本文件把优化计划中的目标与 Preview 0.1 当前可观测能力分开。存在日志或 UI 字段不等于已达到性能目标；没有同条件原始数据时，不填写推测值。

## 端到端字段审计

状态定义：`已验证` 表示本轮真机日志或 overlay 直接出现；`已实现待导出` 表示运行时有值，但没有统一原始时间序列导出；`缺失` 表示 Benchmark 前仍需实现。当前 Android 指标主要显示在本机 overlay，并没有像 iOS `stats` 消息那样全部回传到 Mac，因此不能把“UI 可见”写成“已经可导出”。

| 指标 | 生产者 / 类型 | wire 字段与消费者 | 窗口 / 单位 | 时间序列导出 | 状态 |
| --- | --- | --- | --- | --- | --- |
| requested / actual refresh | `MacSender.swift` session 配置；Android `currentDisplayRefreshRate()` | Mac `ping.requestedFps`、`actualVirtualDisplayRefreshRate` -> `OpenDisplayServer` -> `StreamMetrics` -> `MainActivity` overlay | 配置事件；Hz | 仅 Mac 日志 | 已验证 |
| capture FPS | `MacSender.capFrames` | `ping.capFps` -> Android `lastMacCaptureFps` -> overlay | Mac ping 约 2 s；FPS | 仅周期日志/overlay，无 CSV | 已验证 |
| encoded FPS | `MacSender` VideoToolbox completion window | `ping.encodedFps` -> Android overlay；Mac `ENC-STATS` | 约 1 s；FPS | Mac 文本日志可解析 | 已验证 |
| sent FPS | `MacSender` video send window | `ping.sentFps` -> Android overlay | 约 1–2 s；FPS | 无结构化导出 | 已验证 |
| received FPS | `OpenDisplayServer.receivedFrames` | 不回传；`StreamMetrics.receiverFps` -> Android overlay | `>=1000 ms`；FPS | 无 | 已验证、待导出 |
| decoded FPS | decoder callback `onDecoderFrameDecoded` | 不回传；`StreamMetrics.decodedFps` -> Android overlay | `>=1000 ms`；FPS | 无 | 已验证、待导出 |
| rendered FPS | decoder callback `onDecoderFrameRendered` | 不回传；`StreamMetrics.renderedFps` -> Android overlay | `>=1000 ms`；FPS | 无 | 已验证、待导出 |
| configured / actual bitrate | `StreamEncodingPolicy` / encoded byte windows | `streamConfig.bitrate`、`ping.bitrate`; Android overlay | configured bps；实测需 bytes/time | configured 可见，实际时间序列缺失 | 已实现待导出 |
| encode latency | `MacSender` capture PTS 到 encode completion | `ping.encodeLatencyMs` -> Android overlay；Mac `ENC-STATS` | 约 1 s 平均；ms | Mac 文本日志可解析 | 已验证 |
| decode latency | `VideoFrameTelemetry.decodeLatencyMs` | 不回传；`StreamMetrics.decodeLatencyMs` -> Android overlay | `>=1000 ms` 平均；ms | 无 | 已验证、待导出 |
| latest frame age | `VideoFrameTelemetry.latestFrameAgeMs` | 不回传；`StreamMetrics.latestFrameAgeMs` -> Android overlay | `>=1000 ms` 平均；ms | 无；当前也不是 latest 单样本 | 已实现，命名/导出待修正 |
| estimated E2E latency | `VideoFrameTelemetry.endToEndLatencyMs` + clock offset | 不回传；`StreamMetrics.endToEndLatencyMs` -> Android overlay | `>=1000 ms` 平均；ms | 无 | 已验证、待导出 |
| Mac queue depth | `MacSender.pendingSends` | `ping.queueDepthMac` -> Android overlay；Mac `PHONE-STATS` 后缀仅 iOS 完整 | ping 瞬时值；frames | 无统一导出 | 已验证 |
| Android queue depth | `OpenDisplayServer.queueDepthAndroid` | 不回传；Android overlay | 瞬时值；frames | 无 | 已实现待导出 |
| Mac dropped frames | `MacSender.dropsThisWindow` | `ping.droppedFramesMac` -> Android overlay，发送后清零 | 约 2 s 区间计数；frames | 无统一导出 | 已验证 |
| Android dropped frames | receiver/decoder drop callbacks | 不回传；`StreamMetrics.droppedFramesAndroid` -> overlay，窗口后清零 | `>=1000 ms` 区间计数；frames | 无 | 已实现待导出 |
| RTT | Android 处理 Mac `ping.t`、收到 `pong` 后计算 | `lastRttMs` -> Android overlay | 最近样本；ms | 无 | 已验证 |
| input latency | Mac 输入事件时间窗；Android 仅显示 `inp50` | `ping.inp50`/`inp95` -> Android overlay | 约 2 s 分位数；ms | 无；不是光子到光子输入延迟 | 已实现但定义不足 |
| reconnect time | Mac connection/status/peer-ready 日志 | 无固定 wire 字段 | event delta；ms | 需从文本日志计算 | 已验证但待结构化 |
| CPU / memory / thermal | 当前没有 DisplayWeave producer | 无 | 建议 1 s；%、MB、°C | 无 | 缺失；用系统工具旁路采集 |

### Benchmark 前必须补齐的采集闭环

1. Android 每秒发送结构化 `stats`（包含 receive/decode/render、frame age、E2E、decode latency、queue、drops 和显示 Hz）到 Mac；不得只留在 overlay。
2. Mac 以 monotonic timestamp、session ID 和 transport 把本地 `ping` 字段与 Android `stats` 合并写入 CSV/JSONL。
3. 把当前平均 frame age 明确命名为 `frameAgeAvgMs`，另增 latest、P50/P95/P99，避免字段含义与实现不一致。
4. 增加实际编码/发送 bitrate、CPU、memory、thermal 采样，并记录采样方法与缺失值。
5. 为断开、peer-ready、首帧分别输出结构化 event，才能可靠计算 reconnect time。

## 优化计划功能状态

| 计划项 | Preview 0.1 状态 | 本阶段处理 |
| --- | --- | --- |
| Debug Overlay 完整性能统计 | 大部分底层字段已有 | 先验证字段一致性和导出格式；UI 完整性另行验收 |
| Frame Age | 已实现估算指标 | 在四个场景中作为核心指标采集 |
| HEVC 120 Mbps / H.264 80 Mbps 上限 | 未作为本轮完成项 | 当前已验证配置上限不外推；先建立基线 |
| Manual 10–120 Mbps | 未完成 | 后续按编码器、设备和热稳定性实现 |
| Benchmark 最高 200 Mbps | 未完成 | 不应在普通用户模式开放 |
| Auto 自适应码率 | 未完成 | 先用 RTT、queue、frame age、drop 数据验证阈值 |
| Gaming/Balanced/High 队列模式 | 未完成 | Benchmark 可用实验构建分别测 1/2/3，但不得标作已发布功能 |
| WiFi 2 秒 / USB 1 秒关键帧 | 未完成验收 | 重连/解码错误的强制关键帧已保留；周期策略需独立 A/B 测试 |
| USB 120–160 Mbps 高性能模式 | 未完成 | ADB USB transport 已实现；高码率稳定性仍需测试 |

## 建议的实现与验证顺序

1. 固化 CSV/JSONL 导出字段、时间戳、session ID、transport 和测试场景标识。
2. 对齐 Mac 与 Android 指标采样周期，验证计数器重置和 session 隔离。
3. 在当前稳定码率下完成四场景 WiFi/USB 基线。
4. 增加 Manual 码率并逐级测试 10、20、40、60、80、100、120 Mbps。
5. 只在实验 Benchmark 模式逐级测试 140、160、180、200 Mbps，并设置温度、队列和 frame-age 停止条件。
6. 用基线数据确定“快速下降、缓慢上升”的自适应阈值，再实现 Auto。
7. 最后 A/B 测试 queue depth 与关键帧周期，避免多个变量同时变化而无法归因。

## 性能目标的判定方式

- WiFi `FrameAge < 30 ms`、USB `FrameAge < 20 ms` 是目标，不是 Preview 0.1 的既成事实。
- 120Hz 通过必须同时满足实际显示刷新率、持续 capture/encode/render FPS 与稳定 frame age；仅协商到 120fps 不算通过。
- “明显优于原版”必须使用同设备、同内容、同分辨率、同 codec、同码率的成对测试证明。
- 30 分钟和 2 小时耐久由用户另行执行，本轮文档不伪造结果。

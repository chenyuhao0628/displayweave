[English](performance-metrics-audit.md) | [简体中文](performance-metrics-audit.zh-CN.md)

# DisplayWeave Preview 2.x 性能指标审计（中文）

审计日期：2026-07-11

审计基线：`d5eb716`

范围：macOS Sender 与 Android Receiver。本文只记录代码能够证明的口径；overlay 中存在字段不等于该字段可用于正式 Benchmark。

> 实现状态更新（2026-07-14）：此 Baseline 之后已增加结构化 Benchmark Export 与 Android 热/功耗采样。参见 [Android 热状态与功耗指标](android-thermal-power-metrics.zh-CN.md)；下方历史矩阵保持不改。

## 判定方法

- **真实测量**：由运行时事件、字节数或回调计数得到。
- **配置值**：目标或请求参数，不代表设备实际达到。
- **估算**：依赖跨设备时钟或不能隔离管线阶段。
- **可导出**：当前已有结构化 CSV/JSONL；仅 UI 或自由文本日志均记为否。
- 采样使用 `Date` / `System.currentTimeMillis()` wall clock，而非全链 monotonic clock。凡涉及 Mac 与 Android 两个时钟的值都受系统校时、路径非对称及 offset 误差影响。

## 指标矩阵

| 指标 | 数据来源 | 窗口 / 单位 | 性质与跨时钟影响 | 当前导出 | Benchmark 判定 |
| --- | --- | --- | --- | --- | --- |
| Capture FPS | `MacSender.stream(_:didOutputSampleBuffer:)` 的 `capFrames`；约每 2 秒 `count / elapsed` | ~2 s / FPS | 真实测量；单 Mac 时钟。静态内容下 ScreenCaptureKit 可因内容驱动而自然降低 | 否；仅 ping/overlay 与低帧警告 | 动态测试源下可用，需结构化导出 |
| Encoded FPS | VideoToolbox completion 成功且 Annex B 转换成功后计数 | >=1 s / FPS | 真实测量；单 Mac 时钟 | 部分；Debug `ENC-STATS` 文本和 ping | 可用，但窗口需与 Receiver 对齐 |
| Sent FPS | `NWConnection.send` 的 `contentProcessed` 成功回调 | >=1 s / FPS | 真实的本地 send completion，不代表 peer 已接收 | 否；仅 ping/overlay | 可用，必须按其本地完成语义命名 |
| Received FPS | Android 收到视频 payload 并进入 latest-frame slot 时计数 | 由 render callback 触发的 >=1 s 窗 / FPS | 真实测量；单 Android 时钟；完全无 render 时窗口不会发布 | 否；仅 overlay | 补齐周期发布后可用 |
| Decoded FPS | MediaCodec output buffer dequeue 后的 decoder callback | 同 Android 窗 / FPS | 真实测量；单 Android 时钟 | 否；仅 overlay | 补齐导出后可用 |
| Rendered FPS | MediaCodec `OnFrameRenderedListener` callback | 同 Android 窗 / FPS | 真实回调；不是光子扫描完成时间 | 否；仅 overlay | 高刷新核心指标，补齐导出后可用 |
| Requested FPS | `requestedCaptureFps`、ScreenCaptureKit interval、`streamConfig.fps` | 配置事件 / FPS | 配置值；Android 最终取 `streamConfig.fps`，并未解析 ping 的同名字段 | 配置日志可解析 | 只能作为测试条件，不能作为结果 |
| Actual virtual display refresh | 创建虚拟屏时 `CGDisplayCopyDisplayMode` | 创建事件 / Hz | 真实读取但可能陈旧；后续 HiDPI mode enforcement 不刷新缓存 | 创建日志/ping，无结构化文件 | 周期重读后可用 |
| Android actual display refresh | `Display.getRefreshRate()` | 每 Android metrics 窗 / Hz | 真实读取；overlay 当前展示 requested surface Hz 而非该实际值 | 否 | 修正展示并导出后可用 |
| Target bitrate | `StreamEncodingPolicy` 计算并写入 VideoToolbox；`streamConfig.bitrate` | 配置事件 / bps | 配置值；当前 clamp 为 HEVC 12–80 Mbps、H.264 8–30 Mbps | 配置日志可解析 | 只能作为测试条件 |
| Actual bitrate | send-completion 窗内 wire bytes * 8 / elapsed | >=1 s / bps | 真实本地发送吞吐，含 framing、telemetry 与 Annex B | 仅 Mac UI 瞬时值 | 必须落盘；应另导出 encoded payload bitrate |
| Average frame size | Annex B encoded bytes / encoded frames | >=1 s / bytes/frame | 真实测量；不含 telemetry/framing | Debug 文本/ping，无 CSV | 可用，需注明与 wire bitrate 口径不同 |
| Encode latency | 调用 `VTCompressionSessionEncodeFrame` 前至 completion | >=1 s 算术平均 / ms | 真实 API latency；不是 capture PTS 到 completion | Debug 文本/ping，无 CSV | 改名 `encodeApiLatencyAvgMs`，增加分位数 |
| Decode latency | Mac `snd` wall time 到 Android render wall time | >=1 s 算术平均 / ms | 跨时钟估算；包含网络、排队、解码与上屏，**不是纯 decode** | 否 | 现名不可用于正式结论；改名并另测 MediaCodec 阶段 |
| RTT | Android ping t1，经 Mac pong 回显，到 Android t2 | 最近约 2 s 样本 / ms | 真实往返时间；单 Android 差值但使用 wall clock | 否；仅 overlay | 导出样本和 P50/P95 后可用 |
| Clock offset | `Mac mt - (Android t1 + t2) / 2` | 每 pong 覆盖 / ms | 单次 NTP-style 估算；无低 RTT 筛选、滤波、置信度或稳定状态 | 否，也未进入 metrics | 当前不足以支撑精确跨设备延迟 |
| Frame age | Android receive time 到 render callback | >=1 s 算术平均 / ms | 真实单时钟 receive-to-render；字段虽叫 `latestFrameAgeMs`，实际既非 latest，也不含 Mac/network 前段 | 否 | 改名并增加 latest/P50/P95/P99 后可用 |
| Estimated E2E | Mac `encode()` 入口时间到 Android render，应用 offset | >=1 s 算术平均 / ms | 跨时钟估算；capture 时间点也不是 SCStream callback 入口 | 否 | offset 稳定并给出 confidence 后用于相对 A/B，不作为绝对真值 |
| Mac pending sends / queue | send 前加一、completion 减一的 `pendingSends` | ping 瞬时值 / frames | 真实快照；当前超过 3 才在 capture 前丢帧 | 否 | 需导出时间序列及 P95/P99 |
| Mac dropped frames | backpressure 导致的 pre-encode drop | ~2 s 区间 / frames | 真实计数；ping 后清零，不含所有潜在 drop | 否 | 可用但须明确 drop 分类与累计值 |
| Android queue depth | latest-wins 单 slot 的 0/1 状态 | metrics 发布瞬时值 / frames | 真实快照，极易在采样时恰好为 0 | 否 | 需采样分布/占用时间，不能只用瞬时值 |
| Android dropped frames | latest-slot replacement/保护及 MediaCodec input/oversize/error | >=1 s 混合区间 / frames | 真实计数，但多种原因混在一起 | 否 | 拆分类别后才适合归因 |
| Input P50 / P95 | Android touch 携带经 offset 换算的 Mac time；Mac 到 `CGEvent.post` 后取差 | 累计滚动样本（>240 删除前 120）/ ms | 跨时钟估算；只表示 Android send 到 Mac event post，不是触摸到光子；P95 已发但 Android 丢弃 | 否；仅 P50 overlay | 接通 P95 并导出，可作控制链估算，不可称光子延迟 |

关键代码证据：`Mac/MacSender.swift:585-615,935-993,1013-1033,1146-1171`、`Mac/StreamEncodingPolicy.swift:29-49,74-87`、`Mac/VirtualDisplay.swift:48-97`、`AndroidReceiver/.../OpenDisplayServer.java:211-330,388-475`、`VideoFrameTelemetry.java:18-47`、`H264SurfaceDecoder.java:99-191`、`MainActivity.java:525-586,680-683`。

## 当前可靠测量、配置值与缺失项

### 已有真实运行时测量

Capture/encoded/sent/received/decoded/rendered FPS、实际虚拟屏与 Android 显示 Hz、实际本地发送 bitrate、平均编码帧大小、encode API latency、RTT、Mac pending sends、Mac backpressure drops、Android slot queue/decode drops，以及 receive-to-render frame age 都有运行时代码来源。

这些值目前大多只在 overlay、ping 或文本日志中，不能因此宣称已具备正式 Benchmark 数据集。

### 当前只是配置值

Requested FPS、target bitrate、codec、resolution、quality multiplier、transport 与 VideoToolbox keyframe interval 都是请求/配置。它们必须与 actual refresh、actual bitrate、rendered FPS 和实际 keyframe 数据分列。

### 当前估算或语义不准确

- `decodeLatencyMs` 实为 send-to-render estimated latency。
- `latestFrameAgeMs` 实为窗口平均 receive-to-render latency。
- `endToEndLatencyMs` 依赖单样本 clock offset。
- input P50/P95 只覆盖 Android send 到 Mac `CGEvent.post`。

### 当前缺失

1. Android 到 Mac 的周期结构化 stats 闭环；虽然已有 `statsJson` helper，Android 路径没有调用。
2. Session/run ID、scene、统一时间轴、CSV 与 JSONL。
3. frame age、E2E、RTT、queue 的 P50/P95/P99。
4. 独立的 MediaCodec queue-to-output 与 output-to-render latency。
5. actual encoded payload bitrate 与 actual wire bitrate双口径落盘。
6. 分层 Android drop 原因、Mac 累计 drop、keyframe count/size。
7. Mac CPU、memory；Android CPU、memory、thermal。取不到时必须写 `notAvailable`，不能写 0。
8. 结构化 reconnect/peer-ready/first-frame 事件。

## 跨设备时钟误差

当前 ping/pong 已有 NTP-style 公式，但每个有效样本直接覆盖 offset，只拒绝 `<0` 或 `>=2000 ms` RTT；没有多样本窗口、异常高 RTT 排除、median/lowest-RTT 选择、漂移跟踪、confidence 或 `estimating/unavailable` 状态。两端又使用 wall clock，因此系统校时或手动改时会造成跳变。

在这些问题修复前，receive-to-render 等单 Android 时钟指标可用于比较；E2E、send-to-render 与 input latency 只能标为低置信估算，不应显示虚假精确值。

## 短时 Benchmark 所需最小修改

1. Android 每 >=1 秒发送结构化 stats，包含 receive/decode/render FPS、实际 Hz、frame-age 分布、estimated E2E、RTT、offset 状态、queue 与分类 drops。
2. Mac 将本地 capture/encode/send、target/actual bitrate、frame size、encode latency、queue/drops 与 Android stats 按 session/run/scene 合并。
3. 同时写 CSV 与 JSONL；每行包含 wall timestamp、monotonic elapsed、transport、codec、resolution 和请求参数。缺值使用 `notAvailable`。
4. 修正上述误名；周期重读 virtual display mode；Android overlay 显示 actual Hz；接通 input P95。
5. Debug Benchmark Mode 固定 warm-up/run 时长和场景，只记录真实样本，不自动生成性能数字。

## 码率优化前必须完成的基础工作

- 固定同一设备、commit、分辨率、scale、codec、FPS、内容与 thermal 起点，并先关闭自适应。
- 同时采集 target bitrate、encoded payload bitrate 与 wire bitrate。
- 同时采集 rendered FPS、frame-age 分布、queue 分布、分类 drops、CPU/memory/thermal。
- 建立当前上限下的基线，再逐级测试 Manual 码率；140–200 Mbps 只允许 Benchmark experimental。
- thermal throttle、frame age 持续增长或 queue 达到停止条件时保留失败样本并终止该 run。
- 在上述闭环完成前，不修改码率上限、自适应码率或发送队列。

## 本阶段验证与风险

- Android：`./gradlew --no-daemon clean test assembleDebug`，4 个 self-test PASS，59 tasks，退出码 0。
- macOS：`xcodebuild ... OpenSidecarMac ... CODE_SIGNING_ALLOWED=NO`，退出码 0。
- Website/docs：production build、17 对双语文档检查和 release-link 检查均退出码 0。
- 本阶段只修改审计文档，因此没有“修改前/后性能提升”数据；填写推测性能数字会违反审计目的。
- 风险：现有历史 overlay 数字不能回溯生成缺失的时间序列；后续必须重新采样。

下一阶段应先实现 Android stats 回传、Benchmark recorder 与字段口径修正，再开始任何码率或队列策略修改。

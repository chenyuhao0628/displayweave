[English](android-stability-latency-audit.md) | [简体中文](android-stability-latency-audit.zh-CN.md)

# Android 稳定性与延迟完整审计

审计日期：2026-07-14

分支与版本：`main`，`e6debbcad68a0bac1b0c286fbbbdf1ef2edd7c98`

已检查 Release：`v0.2.0-preview.2`（GitHub 预发布版，发布于 2026-07-14）
审计范围：当前工作区，包括审计开始前已经存在、尚未提交的生命周期和解码器恢复改动。

本文是 Android 连接稳定性与低延迟工作的阶段零审计，记录 Connection Generation 实现前的真实行为。配置的 FPS、码率和刷新率请求不会被当成实测结果；本文也不声称已经完成长时间或多设备验证。

> 实现状态更新（2026-07-14）：PR 1 Connection Generation 至 PR 9 协商式 Binary Framing/分配，以及只增加测量能力的热/功耗 Follow-up 此后均已实现。下表刻意保留阶段零 Baseline；当前行为见[帧尺寸协商](frame-size-negotiation.zh-CN.md)、[Decoder 低延迟选择](android-decoder-low-latency.zh-CN.md)、[WiFi 低延迟 / Surface 帧率](android-wifi-low-latency-surface-frame-rate.zh-CN.md)、[Drop 原因策略](android-drop-reason-policy.zh-CN.md)、[本地快速拥塞下降](mac-local-fast-congestion-decrease.zh-CN.md)、[Binary Framing/分配](android-binary-frame-header-v2.zh-CN.md)与[热/功耗指标](android-thermal-power-metrics.zh-CN.md)。真机恢复证据仍在 [Android 快速恢复 V2](android-quick-recovery-v2.zh-CN.md)中保持待测。

## 执行摘要

当前接收端已经具备可工作的旧版长度前缀 TCP 链路；Android WiFi 与 ADB Forward USB 共用该链路；TCP_NODELAY 已启用；Ping/Pong 遥测已存在；Android 使用容量为一帧的 Latest Frame Wins 队列；UI 会请求匹配的视频/Surface 刷新率。Frame Age 分位数、RTT/时钟偏移、流水线 FPS、队列深度和汇总丢帧数等测量基础也已经存在。

最高优先级问题已经确认：`WifiTcpReceiverTransport.acceptLoop()` 在同一线程内直接调用阻塞式 `readLoop()`。因此旧 Reader 退出之前，Server 无法接受替代连接。当前没有 Connection Generation，Transport 回调也不携带连接身份。旧连接迟到的断开或 Writer 错误因而可能在新逻辑会话已经接管后更新全局状态、释放 Decoder 并停止 Streaming。

后续主要风险是 1 MiB 入站单帧上限、编码前跳过捕获帧仍强制关键帧、缺少按原因分类的 Drop，以及没有协商后的 Session/Config/Frame 身份。Decoder Low Latency、WiFi Low Latency Lock 和本地快速降码率均缺失。这些后续工作不得混入 PR 1。

## 分类说明

- **Implemented（已实现）**：当前活跃路径中存在直接代码证据。
- **Partially Implemented（部分实现）**：已有部分行为，但尚未满足要求的完整不变量或可观测性。
- **Missing（缺失）**：未找到活跃实现。
- **Risk（风险）**：当前行为对应的实际故障模式。
- **Recommended Priority（建议优先级）**：`P0` 阻塞可靠接管/恢复，`P1` 是下一项正确性或延迟风险，`P2` 是优化或测量后续项。

## 27 项审计结论

| # | 问题 | 分类与当前真实行为 | Risk | Recommended Priority |
| --- | --- | --- | --- | --- |
| 1 | 旧 `readLoop()` 结束前能否继续 `accept()`？ | **Missing。** `acceptLoop()` 接受一个 Socket 后直接内联调用 `readLoop(accepted)`，Reader 返回后才会执行下一次 `accept()`。 | 半断开或阻塞的旧 TCP 流会阻止新连接立即接管。 | **P0 / PR 1** |
| 2 | 新连接到达时是否立即关闭旧连接？ | **Partially Implemented。** `accept()` 返回后会调用 `closeClient()`，但第 1 项意味着旧 Reader 阻塞时第二个 Socket 根本到不了这段代码。 | 表面上的替换逻辑无法提供真实的立即接管。 | **P0 / PR 1** |
| 3 | 旧连接晚到断开是否可能覆盖新状态？ | **Risk confirmed。** `onDisconnected()` 没有连接身份，`ReceiverConnectionCoordinator.onDisconnected()` 总会清空队列、释放 Decoder、清除 Connected 并停止 Streaming。 | Stale 回调可以拆掉当前会话。 | **P0 / PR 1** |
| 4 | 当前是否有 Connection Generation？ | **Missing。** Android Receiver Transport 没有 Generation，也没有携带 Generation 的回调。Mac 的拨号 Generation 只保护其出站拨号，不能隔离 Android Receiver 回调。 | 无法确定性拒绝旧 Reader、Writer 和回调。 | **P0 / PR 1** |
| 5 | 当前是否有 Session Epoch？ | **Missing。** | Transport 替换后无法识别旧会话帧。 | **P1 / PR 2** |
| 6 | 当前是否有 Config Version？ | **Missing。** `streamConfig` 只有 Codec/FPS/尺寸/码率/Transport。 | 无法区分旧 Decoder 配置产生的帧。 | **P1 / PR 2** |
| 7 | 当前是否有 Frame Sequence？ | **Missing。** Frame Telemetry 只有捕获和发送时间戳。 | 无法精确归因丢失、乱序、旧帧和首帧时间。 | **P1 / PR 2** |
| 8 | TCP_NODELAY 是否启用？ | **Implemented。** Android 调用 `accepted.setTcpNoDelay(true)`，Mac TCP 参数也设置 `noDelay = true`。 | 活跃 TCP 路径未发现缺口。 | 在 **PR 1** 保留并测试 Socket 配置。 |
| 9 | SO_KEEPALIVE 是否启用？ | **Missing**（Android Accepted Socket）。 | 内核辅助失活检测较弱；KeepAlive 不能替代应用层检测，但应作为辅助。 | **P0 / PR 1** |
| 10 | 当前 Ping/Pong 超时策略是什么？ | **Partially Implemented。** 双方约每 2 秒发送 Ping。Mac 在收到任意 Android Payload 时更新 `lastReceived`，连续超过 5 秒无 Payload 就重连；现有 Mac 重试受断开宽限期约束。Android 会回应 Mac Ping 并估计时钟偏移，但没有对等的有效 Payload 超时关 Socket 策略。 | Android 可能保留半断开连接直到 TCP 报错；Transport 健康和 Video 健康没有分开。 | **PR 1** 先解决身份；完整健康规则后续实现。 |
| 11 | 是否区分 Socket、Hello、StreamConfig、Decoder Ready、First Frame、Streaming？ | **Partially Implemented。** UI 只有 Connected Boolean 和 Streaming Boolean。Decoder 配置或输出格式变化会产生“正在接收”文本，Server 由文本前缀把 Streaming 设为 true，并非由首帧 Render 触发。没有带 Reason/Timestamp 的类型化状态模型。 | UI 可能在画面可见前显示 Streaming，也无法定位恢复卡点。 | **PR 1** 建立状态基础；Ack/Ready 在 **PR 2**。 |
| 12 | 编码前丢帧是否强制关键帧？ | **是，且存在问题。** Pending Send 达到预算时，`SendQueuePolicy.decision()` 返回 `forceKeyframe = true`；该捕获帧尚未进入 VideoToolbox，`MacSender` 就设置 `needsKeyframe`。 | 本地发送压力会制造不必要 IDR 与带宽尖峰。 | **P1 / PR 3** |
| 13 | 关键帧请求是否可能重复触发？ | **是。** Mac 的 `needsKeyframe` Boolean 能在下一次 Encode 前合并部分请求，但 Android 的缺 SPS、Config 改变、Decoder 异常、重连/静态画面恢复和 Stall Recovery 都可能发送 `kf`，没有恢复周期 ID 和原因计数。 | Decoder 恢复附近仍可能出现多余关键帧突发，且原因不清。 | **P1 / PR 3** |
| 14 | 长度前缀协议最大单帧多大？ | **Implemented 的安全限制：Android 入站 1 MiB。** `MAX_FRAME_BYTES = 1 << 20`。Mac 发送 UInt32 长度，没有对应的出站大小保护。 | 合法大 IDR 可能超过 Android 上限。 | **P1 / PR 4** |
| 15 | 超过上限会怎样？ | **Partially Implemented 的安全处理。** Android 在分配 Payload 前拒绝 `length <= 0` 或 `> 1 MiB` 并抛 `IOException`；当前 Transport 将其报告为普通断开/错误并关闭当前 Socket。没有 Oversize 指标、协商上限或专用恢复原因。 | 单个大关键帧会断开整个流，且难以诊断。 | **P1 / PR 4** |
| 16 | 是否使用 `KEY_LOW_LATENCY` / `FEATURE_LowLatency`？ | **Missing。** | 当前 Decoder 没有显式开启受支持的 Low Latency 模式。 | **P1 / PR 5** |
| 17 | 是否记录实际 Decoder 名称？ | **Missing。** 使用 `MediaCodec.createDecoderByType()`，未发布 `codec.getName()`。 | 无法把设备行为关联到实际 Codec 实现。 | **P1 / PR 5** |
| 18 | 是否区分硬件/软件 Decoder？ | **Missing。** 没有 `MediaCodecInfo` 硬件、软件、Vendor 能力报告。 | 软件回退可能被误判为网络拥塞。 | **P1 / PR 5** |
| 19 | 是否使用 `Surface.setFrameRate()`？ | **Implemented，但有缺口。** API 30+ 会设置 Window Preferred Refresh Rate，并调用两参数 `Surface.setFrameRate(target, FIXED_SOURCE)`；状态和日志区分请求/实际值。尚未使用 API 31 的 Seamless-only 策略重载，重应用与清理生命周期也未显式建模。 | 刷新率请求不如候选 Seamless-only 策略可控。 | **P2 / PR 6** |
| 20 | `dequeueInputBuffer(0)` 当前行为？ | **Implemented 为非阻塞轮询。** 如果 Input Buffer 当下不可用，直接 Drop 并计入 Android 汇总 Drop。 | 调度抖动会变成无法归因的 Decoder Drop；尚无 0/250/500 us A/B。 | **P2，先实验后考虑异步改造** |
| 21 | 是否有 Android WiFi Low Latency Lock？ | **Missing。** | WiFi 节电调度可能增加延迟，但收益和功耗尚未知。 | **P1 / PR 6**，必须有能力与生命周期保护。 |
| 22 | 是否有 Buffer Pool？ | **Missing。** Framing、Telemetry Strip、NAL 提取和 Decoder CSD 都会创建数组/Data。 | 分配与 GC 可能恶化 120fps 长尾。 | **P2 / PR 9，先测量** |
| 23 | 每帧是否重复扫描 VPS/SPS/PPS/Keyframe NAL？ | **是。** Queue Importance 会扫描；Decoder 启动分别调用 `findNalUnit` 查 VPS/SPS/PPS；关键帧 Flag 又扫描一次。`AnnexB.nalUnits()` 还会把每个 NAL 复制到新数组。 | 热路径重复执行 O(frame size) 工作并产生分配。 | **P2 / PR 9** |
| 24 | Drop 是否按原因分类？ | **Missing。** Android 和 Mac 只有汇总 Drop；没有要求中的原因枚举/计数。 | 恢复与自适应码率无法区分拥塞、Stale、Surface 丢失、Decoder Input 压力和重配置。 | **P1 / PR 7** |
| 25 | Auto Bitrate 是否把所有 Android Drop 当拥塞？ | **是。** 任何正数 `androidDrops` 都返回 `android-drops` 拥塞原因；稳定恢复也要求 Android Drop 为零。 | 生命周期或 Decoder 非拥塞 Drop 会错误降低码率。 | **P1 / PR 7** |
| 26 | 是否有热状态和节电状态指标？ | **Missing。** | Thermal Throttling 和 Power Saver 可能伪装成 Decoder/网络退化。 | **P2，仅测量阶段** |
| 27 | 是否已有快速本地拥塞止损？ | **Missing。** 编码前 Queue Budget 会立即 Drop，但 Bitrate Evaluate 由约 1 秒一次的 Receiver Stats 驱动；没有使用 Pending Send Age/Completion Delay 的 100–250ms 只降不升控制器。 | 本地队列增长可能持续到 Receiver 控制环响应。 | **P1 / PR 8** |

## 阶段零补充发现

### 连接所有权

- Transport 只有全局 `socket` 和全局 `output`，没有不可变的 Per-Connection Context。
- Writer Executor 虽然串行，但排队任务执行时解析全局 Output，无法表明该写入属于哪一代连接；Writer Failure 也不受 Generation 约束。
- `isActive(Socket)` 只能在替换已经发生时阻止旧 Reader 的 `finally` 断开另一个 Socket；由于内联 Reader 阻塞期间替换无法发生，它不能解决半断开接管。
- `ReceiverConnectionCoordinator` 无条件执行，没有 Stale Event 结果或结构化 Transition。
- `decoderWorker` 中排队的视频任务只有 Payload/Telemetry，没有连接身份，接管后无法拒绝旧工作。

### 必须保留的已有基础

- 旧版 4 字节大端长度前缀和 JSON/Annex-B Payload。
- 旧 Android/iOS Hello/Control 兼容与 `_opensidecar._tcp`。
- Android Latest Frame Wins 单帧队列与重要帧保护。
- Mac 1～3 帧发送队列预算；不能通过扩大队列隐藏延迟。
- 现有有限重连/宽限、ADB Forward 生命周期、Codec Fallback 和静态画面关键帧重放。
- Frame Age P50/P95/P99、RTT/Clock Offset、捕获/编码/发送/接收/解码/渲染计数和 Benchmark CSV/JSONL。
- 当前刷新率请求与实际 Android Display Hz 报告。

## 优先级与 PR 边界

### PR 1——当前实施

1. 将 Acceptor 与各连接 Reader 分离，使 `accept()` 持续可用。
2. 增加单调递增的 Android Connection Generation 和不可变 Connection Context。
3. 原子替换 Current Connection，再关闭旧 Socket。
4. Connected/Payload/Disconnected/Error/Write 全部携带并校验 Generation。
5. 只有 Current Generation 可以更新 UI、重置/释放 Decoder、发布连接状态或写数据。
6. 每个 Accepted Socket 启用 TCP_NODELAY 与 SO_KEEPALIVE。
7. 增加包含 Reason、Timestamp、Generation 的类型化应用层连接状态。PR 1 不得伪装已经具备 Epoch/Config Ack。
8. 增加确定性测试：旧 Reader 晚到断开、旧 Writer 晚到失败、快速双连接、阻塞旧连接被替换、仅 Current 可断开、仅 Current 可写。

### 明确延后

Session Epoch/Config Version/Frame Sequence 与 Stream Ack 属于 PR 2；关键帧/Drop 策略属于 PR 3；单帧上限协商属于 PR 4；MediaCodec Low Latency 属于 PR 5；WiFi Lock/Surface 完善属于 PR 6；Drop Filter 属于 PR 7；本地快速降码率属于 PR 8；Protocol V2/Buffer 属于 PR 9。PR 1 不得加入 UDP、QUIC 或异步 MediaCodec 重构。

## Baseline 证据与验证边界

仓库已有短时 Benchmark 和恢复检查流程，但尚无本轮候选改动的同条件真机 A/B 数据。因此：

- **Before/After Metrics：** 暂无，不声称延迟已经降低。
- **Known Risks：** PR 1 之后仍会保留 1 MiB 单帧上限、汇总 Drop、编码前 Drop 强制 IDR，以及缺失 Decoder/WiFi Low Latency 能力处理等风险。
- **Pending Physical Validation：** WiFi 与 ADB USB、HEVC 60/120、快速重连、半断开替换、Android 前后台、USB 拔插、ADB 重启，以及旧 OpenDisplay iOS Receiver 兼容性。

[English](android-drop-reason-policy.md) | [简体中文](android-drop-reason-policy.zh-CN.md)

# Android Drop 原因与自适应码率策略

## Modified Files

- Android Receiver：原因模型/Tracker、协议统计、Decoder 与 Transport Drop 产生点及确定性 Self-test；
- Mac Sender：Receiver Stats 解码、Benchmark CSV/JSONL 字段、Adaptive Controller 过滤与 Standalone Test；
- 文档索引、阶段零状态和双语文档校验。

## Purpose

PR 7 用可归因的窗口/累计计数替代含义模糊的 Android 汇总 Drop 信号，并避免把 Lifecycle、Stale Identity、Malformed Input、Transport Transition 与 Codec Reconfiguration Drop 解释成网络拥塞。

汇总字段 `androidDroppedFrames` 继续供 UI 和旧 Mac Build 使用。新 Mac Build 消费下述附加字段；Framing 和 Legacy iOS 行为不变。

## Classification and Evidence

Receiver 使用以下稳定 Reason Key：

| Reason | 作为拥塞输入 | 含义 |
| --- | --- | --- |
| `latestSlotReplaced` | 是 | 新帧替换单槽 Pending Frame |
| `importantFrameProtected` | 是 | 为保护已排队重要帧而拒绝普通新帧 |
| `decoderInputUnavailable` | 是 | MediaCodec 当下没有 Input Buffer |
| `frameAgeExpired` | 是 | 未来 Age Policy 丢弃过期工作 |
| `decoderInputOversize` | 否 | Decoder Input Capacity 小于帧 |
| `decoderException` | 否 | Decoder 拒绝工作或进入 Illegal State |
| `surfaceUnavailable` | 否 | 没有有效 Render Surface |
| `staleConnectionGeneration` | 否 | 工作属于旧 Connection Generation |
| `staleSessionEpoch` | 否 | 协商 Session Identity 已过期 |
| `staleConfigVersion` | 否 | Config Identity 或帧顺序已过期 |
| `invalidFrameLength` | 否 | Framing 拒绝非法或超限长度 |
| `malformedAnnexB` | 否 | Video Payload 没有可用 Annex-B NAL Unit |
| `codecReconfigureDrop` | 否 | Decoder/Config 替换使工作失效 |
| `transportReadFailure` | 否 | 当前 Transport Read 失败 |
| `transportWriteFailure` | 否 | 当前 Transport Write 失败 |
| `referenceChainBroken` | 否 | 已编码预测帧被丢弃；后续依赖帧等待新的关键帧 |

每个已记录事件包含 `reason`、`countWindow`、`countTotal`、`generation`、`sessionEpoch`、`configVersion`、`frameSequence`、`codec` 与 `transport`。Receiver Stats 发布：

- `androidDropCountsWindow` 与 `androidDropCountsTotal`；
- `androidCongestionDrops` 与 `androidDropTotal`；
- 带完整 Identity Context 的 `androidLastDrop`。

旧 Generation Callback 仍被隔离，不能修改当前 Decoder 或连接状态。分类字段是附加 JSON，旧 Sender 可以安全忽略。

## Adaptive-bitrate Filtering

Auto Bitrate 不再因为 `androidDroppedFrames > 0` 就下降。只有连续两个 Receiver-stat Window 都出现 `androidCongestionDrops`，才按已分类 Decoder Throughput Pressure 降低码率。单个分类窗口会阻止 Stable Increase，但不会立即降码率。

非拥塞 Android Drop 既不会触发下降，也不会阻止现有五秒 Stable Recovery。已有独立输入继续生效：Mac Pending Send/Drop、持续 Android Queue Depth、Sent/Encoded Deficit、RTT 上升与 Frame Age 上升。

连接不含分类字段的旧 Receiver 时，Mac 将 Classified Android Congestion 视为零，继续使用上述独立信号，不根据 Legacy Aggregate Count 猜测拥塞。

## Tests

- Failure-first Android Test 覆盖全部 16 个 Reason Key、拥塞成员、窗口/累计计数、Reset 行为与完整 Last-event Context；
- Protocol Test 覆盖嵌套 Reason Map 与 Last-event JSON；
- Adaptive-controller Test 证明 Unclassified/Non-congestion Drop 被过滤、单窗口不足、连续双窗口才下降，且被过滤 Drop 不阻止 Stable Recovery；
- Benchmark Test 覆盖 Reason Map、Congestion Count、Identity Context、稳定且唯一的 CSV Column 与 JSONL Output。

## Build Result

- Android `clean test assembleDebug`：通过，61/61 Tasks 均执行；六组 Self-test 全部报告 PASS，Debug APK 成功组装；
- Mac Standalone Test：21/21 通过，包括 Adaptive Filtering 与稳定且唯一的 Benchmark Column；
- `xcodegen generate`：通过；
- 关闭签名的 macOS Debug Build：`BUILD SUCCEEDED`；
- 关闭签名的 Generic iOS Simulator Debug Build：`BUILD SUCCEEDED`，Legacy iOS 路径保持可构建；
- 网站 Production/SSR/Prerender Build：通过；
- 双语文档检查：通过，30 对带互链文档，包括 PR 7；
- Release-link Check 与 `git diff --check`：通过。

## Before/After Metrics

尚未采集真机 A/B。本 PR 改变的是归因和 Controller Input 语义，不声称 Frame Age 已降低、Drop 已减少或吞吐已提高。新增 Reason Field 让后续同条件证据可以按原因拆分。

## Known Risks

- Reason Classification 描述软件观察点，不能证明硬件或网络根因；
- `latestSlotReplaced`、`importantFrameProtected` 与 `decoderInputUnavailable` 只有持续出现时才是 Throughput Pressure 证据，因此使用双窗口过滤；
- 旧 Receiver 没有 Reason Field，Controller 会依赖 Queue、RTT、Frame Age 与 Sender-side Signal，而不会猜测；
- 当前非阻塞 `dequeueInputBuffer(0)` 行为不变，0/250/500 µs 实验仍是独立工作。

## Pending Physical Validation

- 采集同条件 WiFi 与 ADB USB 样本，核对 Aggregate Drop 与 Reason-window Sum；
- 制造 Surface 丢失、前后台切换、Transport 替换与 Decoder 重配置，确认它们不会触发 Android-drop 降码率；
- 制造持续 Decoder Pressure，确认仅在两个分类窗口后下降；
- 在 Queue Depth、Codec、FPS、Bitrate Bound 与 Scene 不变时比较前后 Rendered FPS 和 Frame Age P50/P95/P99。

实现期间没有连接 Android 设备，因此 Build Success 不是实体性能证据。

## Next Step

PR 8 见[本地快速拥塞策略](mac-local-fast-congestion-decrease.zh-CN.md)，PR 9 已在 [Android Binary Framing/分配](android-binary-frame-header-v2.zh-CN.md)中实现。剩余步骤是真机兼容/恢复证据。

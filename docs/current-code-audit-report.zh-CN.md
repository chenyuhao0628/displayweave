[English](current-code-audit-report.md) | [简体中文](current-code-audit-report.zh-CN.md)

# 当前代码审计报告

生成时间：2026-07-15（Asia/Shanghai）  
审计 HEAD：`79cbf90fdc61bf296a222a10750b2fa7f0a2df1f`  
Preview 5 目标：`4276c1a229f9f0b3237242d3ebbc0f29d7e244da`（当前 HEAD 领先两个提交）  
基线工作区：干净  
真机验证：**Pending——`adb devices -l` 没有已连接设备**

## 首轮九问

1. **旧异步 MediaCodec Callback 会污染当前状态吗？会（P0）。** Input/Output/Error/Format 检查 Codec 身份，但 Frame Rendered 没有；时间戳从零重启时旧回调可消费当前 Telemetry。现已为所有 Callback 增加 Decoder Generation + Codec 校验。
2. **Input Buffer index 所有权严格吗？原来不严格（P1）。** 队列没有重复保护；现已增加所有权 Set，并在全部生命周期边界与队列同步清理。
3. **Pending P 帧替换会破坏参考链吗？原理上会；补正后的策略显式处理。** 进入 Awaiting Keyframe、拒绝依赖帧、只请求一次恢复，并识别 H.264 IDR 与包含 CRA 的 HEVC IRAP 16–23。
4. **`renderedTelemetry` 有无界增长风险吗？有（P0）。** 现限制为 512 条，淘汰最旧条目并保留 Peak/Evicted 计数。
5. **Combined Pending Work 会计数错误吗？补正前会（P1/P2）。** 现由不可变 Encoder Generation 拥有 Work；旧 Completion 不能减少或进入当前 Codec，重复/未匹配 Completion 被拒绝，Encode 前合并预算默认值不变。
6. **Decoder 能力上限与实际路径一致吗？原来不能保证；静态不一致已本地修复。** 广告使用默认运行时候选排序；HEVC 首选时取所选 HEVC 与 H.264 回退共同上限。厂商误报与运行时回退保持真机 Pending。
7. **发现 P0/P1 吗？发现。** 两个 P0 与已识别静态 P1 均已本地补正并由确定性 Policy/State Test 覆盖；硬件/厂商行为不能由源码测试关闭。
8. **哪些只有代码、没有真机证据？** 异步 Callback、MediaCodec Low Latency、WiFi Lock、Surface Frame Rate、90/120Hz 映射、Decoder 能力限制、USB/WiFi 接管、Codec 回退、Binary V2、温控/电量指标、真实 FPS/延迟/恢复，以及 Legacy iOS/旧 Android 兼容。
9. **第一个推荐 PR？** “Async MediaCodec ownership and stale callback safety”。只包含 Callback Generation、Input index 所有权、有界 Telemetry、确定性测试和终止错误交接，不混入 FPS/ABR/协议修改。

## 分级摘要

| ID | 级别 | 状态 | 摘要 |
| --- | --- | --- | --- |
| ADC-001 | P0 | 本地已修 | 旧 Frame Rendered Callback 访问共享当前 Telemetry |
| ADC-002 | P0 | 本地已修 | Rendered Telemetry Map 无界 |
| ADC-003 | P1 | 本地已修 | 重复 Input index 未拒绝 |
| ADC-004 | P1 | 本地已修；真机 Pending | 终止 Codec Error 进入合并的重建/回退恢复 |
| REF-001 | P1 | 本地已修并测试 | HEVC IRAP/CRA 恢复分类 |
| WB-001 | P1 | 本地已修并测试 | Pending Encode 与旧 Callback 按 Encoder Generation 隔离 |
| FPS-001 | P1 | 本地已修；真机 Pending | 广告能力使用默认运行时候选排序 |
| FPS-002 | P1 | 本地保守修复 | 广告上限同时适用于选中 HEVC 与 H.264 回退路径 |
| MET-001 | P2 | 本地已修并测试 | 累计 GC 计数被误作窗口指标 |

## 已确认活跃路径实现

代码与自动测试确认 Connection Generation、独立 Accept/Read、Current Socket 接管、Session Epoch、Config Version、Frame Sequence、V2 Progress Ack、Legacy Fallback、Keyframe Coalescing、Frame Limit 协商、Decoder/WiFi Low Latency Mode、Surface Frame Rate 生命周期、Drop 归因、本地快速降码率、Binary V2 零拷贝 View、Thermal/Power、异步 MediaCodec、Latest Pending Compressed Frame、Reference Chain Recovery、Decoder 能力上限和 90→更高刷新率映射。以上是实现结论，不是实测性能结论。

Legacy Protocol-level Compatibility 已由能力门控和逐字节 Framing Test 验证；OpenDisplay iOS 与旧 Android 真机兼容为 Pending。

## 身份边界

| Event | 必需身份 | 结果 |
| --- | --- | --- |
| Transport Callback | Connection Generation | Transport Context + Coordinator 强制 |
| StreamConfig | Generation + Epoch + Config | V2 强制 |
| Video Frame | Generation + Epoch + Config + Sequence | V2 强制；Legacy 按设计无 V2 身份 |
| Decoder Callback | Decoder Generation + Active Codec/Session | Decoder 本地已补正；Server Listener 再查连接/会话/配置 |
| First Frame | Epoch + Config + Sequence | V2 通过 Telemetry 强制；真机 Pending |
| Stats | Current Session only | 交付有身份保护；Drop Window 与 GC Delta 显式重置 |

## 自动证据

`AndroidReceiver` 中执行 `./gradlew --no-daemon clean test assembleDebug`，BUILD SUCCESSFUL；六组 SelfTest 全部 PASS。抽出的 Decoder Callback State 已确定性覆盖旧 Generation、Duplicate Input Index、生命周期清理和 Telemetry Bound；真实厂商 Callback Timing/Surface Race 仍为 Pending。

其他 Gate：22 个 Swift Standalone Suite 全部通过；macOS Debug 与未签名 iOS Simulator Build 成功；Site Build、双语文档、Release Link、`git diff --check` 通过。Preview 5 Tag/Workflow/七个资产/Hash/APK Signer 与版本/Mac 版本/Appcast/Android Manifest/线上 Feed 已独立验证。DMG Checksum 通过，本地 Mount Layout 因环境限制 Pending。

## 发布建议

不得把 Preview 5 描述为已真机验证或生产稳定。静态 P0/P1 补正可按推荐边界拆分 PR；下一 Preview 应等待 WiFi/USB、Codec、刷新率、恢复与 Legacy 真机矩阵，或在发布中醒目标记这些项目为 Pending。

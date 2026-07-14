[English](frame-size-negotiation.md) | [简体中文](frame-size-negotiation.zh-CN.md)

# Android 帧尺寸协商与超限保护

本文记录 Android 稳定性工作的 PR 4。它在不取消长度校验、不改变旧 iOS Wire Path、也不引入 Frame Chunking 的前提下，提高 Android Protocol V2 可用的单帧上限。

## Purpose

此前 Android Reader 会拒绝所有超过 1 MiB 的长度前缀 Payload，合法的大 IDR 因而可能表现为普通网络断开。PR 4 把上限变成显式协商值，在分配 Payload Buffer 前拒绝无效输入，并输出足够的指标以区分真实 Frame Growth 与 Malformed Input。

## Negotiation and Limits

Android 在 `hello` 中声明新增 Capability 与数值：

```json
{
  "protocolVersion": 2,
  "capabilities": ["maxFrameBytes"],
  "maxFrameBytes": 8388608
}
```

该 Capability 是现有完整 Protocol V2 Identity/Progress Capability Set 的增量。Mac 只对完整协商成功的 Android V2 Peer 使用它，并在 V2 `streamConfig` 中回显经过约束的值。

当前限制如下：

| Path | Limit | Rule |
| --- | ---: | --- |
| Legacy Length-prefix Reader | 1 MiB | 保持不变 |
| Android Protocol V2 Default | 8 MiB | 仅由 V2 `streamConfig` 启用 |
| Absolute Parser Ceiling | 16 MiB | 永远不可绕过 |

每个 Android Connection 最初都使用 1 MiB Legacy Limit。Reader 先解析体积很小的 `streamConfig` Control Payload；V2 Configuration 随后把该连接的 Reader Limit 提高到 Receiver 声明的最多 8 MiB，Legacy Configuration 则继续保持 1 MiB。更新在 Reader 接受下一帧视频之前完成，因此首个 Negotiated Large Keyframe 不会落入异步配置竞态。

Mac 在写入 4 字节 Length Prefix 之前，先检查已编码的 V2 Video Payload 是否超过协商值。若超限，Payload 不会发送，事件会被明确记录，并进入现有有限 Reconnect Policy。未声明 `maxFrameBytes` 的 Peer 保持未改动的 Legacy Send Path。

## Rejection Behavior

Android 在分配 Payload Buffer 前验证 4 字节大端长度，并区分：

- `invalid_length`：长度为零或负数；
- `oversize`：超过当前连接协商限制；
- `absolute_limit`：超过 16 MiB。

Transport 发布类型化 Reason、Byte Count、Limit 与 Connection Generation，只关闭 Current Connection，并复用现有有界重连生命周期。Stale Connection 的迟到拒绝不能更新当前 Receiver 状态。本 PR 没有增加无限 Length、无限 Retry、无限 Queue 或 Frame Chunking。

## Metrics

Receiver Stats 与 Mac CSV/JSONL Benchmark 现在包含：

- `currentFrameBytes` 与 `maxFrameBytesObserved`；
- `currentKeyframeBytes` 与 `maxKeyframeBytesObserved`；
- `oversizeFrameCount` 与 `invalidFrameLengthCount`。

“Current Keyframe”指最近一次接受的关键帧。新连接会重置 Current 值，Observed Maximum 和 Rejection Total 在 Receiver 进程运行期间累计。Keyframe Classification 会先移除现有 Telemetry Prefix，再识别 H.264 IDR NAL Type 5 与 HEVC IRAP NAL Type 19/20。

## Modified Files

- Android Protocol、WiFi Transport、Server、Frame Classifier、Stats Snapshot，以及新的 `FrameSizeMetrics` 累加器；
- Mac Capability Parsing、Frame-size Policy、V2 Stream Configuration、Sender Guard 与 Benchmark Schema；
- Android/Mac Failure-first Self Test；
- 本双语文档与文档索引。

## Tests

专项测试覆盖 Legacy 1 MiB 拒绝、V2 大于 1 MiB 的 Payload 接受、精确 8 MiB 接受、超过 8 MiB 的类型化拒绝、16 MiB Absolute Ceiling、零长度、按 Connection Generation 隔离的拒绝、Capability Parsing/Clamp、V2 Echo、Legacy Omission、Keyframe Classification、全部六项指标，以及稳定的 Benchmark CSV/JSONL Column。

## Build Result

2026-07-14 已完成：

- Android `./gradlew --no-daemon clean test assembleDebug`：通过，61 个任务及全部 6 组 Self Test；
- 全部 21 个 Mac Standalone Self Test：通过；
- `xcodegen generate`：通过；
- `OpenSidecarMac` macOS Debug（关闭 Code Signing）：通过；
- `OpenSidecariOS` Generic Simulator Debug（关闭 Code Signing）：通过；
- `pnpm build`、26 对双语文档检查、Release Link Check 与 `git diff --check`：通过。

## Before/After Metrics

PR 4 尚未采集同条件真机 A/B 数据，因此不声称 Frame Age 更低、吞吐更高或重连更少。新增字段用于在下一次真机运行中测量最大 Frame/Keyframe Size。

## Known Risks

- 8 MiB 已有确定性边界测试，但尚未在受控真机负载中验证；
- Sender 仍以一个 Length Prefix 承载一整帧，Chunking 继续延期；
- Keyframe Classification 仍执行 Annex-B Scan 与分配，属于后续 Buffer/NAL Optimization 阶段；
- 旧 iOS TestFlight Receiver 的 Runtime Compatibility 仍需真机检查；本 PR 未改变其协议字节。

## Pending Physical Validation

- 在 Android WiFi 与 ADB USB HEVC 60/120 下采集最大 Frame/Keyframe Size；
- 在设备上主动注入 Oversized Header，确认类型化 Log、有限重连且无 OOM；
- 验证旧 OpenDisplay iOS 的 Video/Input/Ping/Reconnect；
- 在同场景同设置下比较 Frame Age P50/P95/P99 与 Keyframe Peak。

最终 PR 4 Verification 时没有连接 Android 设备，因此这些项目明确保持 Pending，不会从桌面测试结果推断为已完成。

## Next Step

PR 5 应实现 MediaCodec Low-latency Capability Selection 与 Fallback Reporting，不混入 WiFi Lock、Surface Policy 或异步 MediaCodec Input。

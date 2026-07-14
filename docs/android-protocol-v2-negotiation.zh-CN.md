[English](android-protocol-v2-negotiation.md) | [简体中文](android-protocol-v2-negotiation.zh-CN.md)

# Android Protocol V2 协商

本文描述 PR 2：在 PR 1 Connection Generation 之上，为 Android 增加可协商的 Session Identity 与 Receiver Progress Report。本 PR 不引入后续 Binary Frame Header，也不改变旧 OpenDisplay iOS Receiver 路径。

## Purpose

PR 1 防止旧 TCP Connection 的回调修改新连接。PR 2 继续隔离同一 Current Connection 内的 Stream，使旧 Stream Config 的 Frame 与 Decoder Callback 不能被误认为当前 Stream。

```text
Connection Generation -> Session Epoch -> Config Version -> Frame Sequence
```

## Capability Negotiation

Android Hello 声明 Protocol Version 2 和完整 Capability Set：

```json
{
  "protocolVersion": 2,
  "capabilities": [
    "streamConfigAck",
    "decoderReady",
    "firstFrameRendered",
    "sessionEpoch",
    "configVersion",
    "frameSequence",
    "maxFrameBytes"
  ],
  "maxFrameBytes": 8388608
}
```

只有 Peer 明确识别为 Android 且 PR 2 的六项核心 Capability 都存在时，Mac 才启用 Identity/Progress 行为。PR 4 将 `maxFrameBytes` 作为单独 Gate 的扩展；参见[帧尺寸协商](frame-size-negotiation.zh-CN.md)。Version 缺失、核心 Capability 不完整、旧 Android Hello 或 iOS Hello 都选择未改动的 Legacy Path。

## Identity Rules

1. Mac Transport Connection 每次进入 `ready` 都从进程级单调分配器取得新的 `sessionEpoch`，包括由替换后的 `MacSender` 实例创建的连接。
2. 新 Session 重置 `configVersion` 与 `frameSequence`。
3. 每次发送 `streamConfig` 都递增 `configVersion` 并重置 `frameSequence`，包括 Reconnect、Codec Fallback、Reconfiguration 和有限协议重试。
4. 每次提交 Encoded Frame 时递增 `frameSequence`。Encode 失败可以产生 Sequence Gap，不要求连续。
5. Negotiated `streamConfig` 携带 `protocolVersion`、`sessionEpoch` 和 `configVersion`。
6. Negotiated Video Frame 保留现有 JSON Telemetry Prefix，并增加 `se`、`cv`、`fs` 字段；本 PR 不发送 Binary V2 Header。
7. Android 仅在 Connection Generation、Session Epoch、Config Version 均为 Current 且 Frame Sequence 严格更新时接受 Frame。
8. Stale 或 Duplicate Frame 不进入 Latest-frame Slot，也不进入 MediaCodec。
9. Android 新连接在接受有效 `streamConfig` 前没有有效 Stream Identity。

## Receiver Progress

Negotiated Android Session 会发送：

- 验证并应用当前 Config Identity 后发送 `streamConfigAck`；
- MediaCodec 成功启动后才发送 `decoderReady`，包含实际 Decoder Name 和硬件/软件/低延迟能力报告；
- 只有 Current Identity 的 Rendered-frame Callback 才发送 `firstFrameRendered`；
- `connectionState` 包含 State、Reason、Entered Time、Generation、Session Epoch 和 Config Version。

状态顺序：

```text
SOCKET_CONNECTED -> HELLO_SENT -> HELLO_ACCEPTED
-> STREAM_CONFIG_RECEIVED -> STREAM_CONFIG_ACCEPTED
-> DECODER_CONFIGURING -> DECODER_READY
-> WAITING_FIRST_FRAME -> STREAMING
```

对于 Negotiated Peer，Mac 在收到匹配的 `firstFrameRendered` 前不会显示 `已连接 / Streaming`。Stale、Duplicate 和乱序 Progress Event 会被忽略。

## Decoder Reconfiguration Safety

仅由 Adaptive Bitrate 变化产生的 `streamConfig` 仍会获得新的 Config Identity，但不会销毁兼容的 MediaCodec。Android 会把 Decoder Callback 重新绑定到新 Identity，重新发布 `decoderReady`，并等待携带新 Config Version 的 Frame。Codec、FPS 或尺寸变化仍会替换 Decoder。Negotiated Decoder 停滞时，Android 会先把旧 Decoder 标记为不可用，并同时请求新的 `streamConfig` 与关键帧；Mac 先发送 Config，使 `configVersion` 递增，再强制 IDR。Legacy Recovery 保持原有的仅请求关键帧行为。可能阻塞在 Vendor 实现中的 `MediaCodec.stop()`/`release()` 会在 Decoder Worker 执行，而不是阻塞串行 Transport-event Executor，因此 Ack、Ping 与更新的 Config 仍可继续处理。

## Finite Timeout Policy

- StreamConfig Ack：1.5 秒；
- Decoder Ready：2 秒；
- First Frame：3 秒。

超时会使用新 Config Version 重发 `streamConfig` 并请求关键帧。整个 Handshake 共用两次重试预算；耗尽后最多重连一次，第二次 Handshake 仍失败就明确结束 Session。只有实际首帧 Render 才重置跨连接预算，因此失败路径不会无限重试。

## Legacy Compatibility

- 外层 4 字节大端长度前缀不变。
- Legacy iOS 继续收到完全相同的 `{"cap":...,"snd":...}` Telemetry Prefix 与 Annex-B Video。
- Legacy `streamConfig` 不包含 Protocol Version、Epoch、Config Version，也不要求 Ack。
- 不向 iOS 发送 Binary Frame Header、Mandatory Ack 或未知二进制 Payload。
- 现有 Ping/Pong、Touch、Scroll、Cursor、Stats、Codec Failure、Keyframe Request 和 Goodbye 消息继续有效。

## Modified Files

- `Mac/DeviceCapabilities.swift`：完整 Capability Gate 与 Legacy Fallback。
- `Mac/StreamEncodingPolicy.swift`：进程级 Session Epoch、Config/Frame Identity、Telemetry Prefix 与有限 Handshake Policy。
- `Mac/MacSender.swift`：Identity 生命周期、Negotiated Output、Progress 处理、UI 阶段和超时重试。
- `LengthPrefixedProtocol.java`：Capability 声明和 PR 2 Control Message。
- `ReceiverProtocolSession.java`：Current Identity 与 Stale-frame Filter。
- `VideoFrameTelemetry.java`：Epoch/Version/Sequence 解析。
- `H264SurfaceDecoder.java`、`DecoderRuntimeInfo.java` 与 `DecoderReconfigurationPolicy.java`：实际 Decoder-ready 证据与兼容 Decoder 复用。
- `OpenDisplayServer.java`：协商、Ack、Identity Check、Progress Publication 与非阻塞 Decoder Replacement Scheduling。
- 状态 Snapshot/Coordinator/UI 文件和 Android/Mac Self Test。

## Tests

Failure-first Test 覆盖完整与不完整协商、Legacy iOS Fallback、进程级 Epoch 单调性、Version/Sequence 生命周期、Stale 与 Duplicate Frame 拒绝、首帧正 Sequence、Progress JSON、乱序 Progress 拒绝、两次 Retry 后失败、跨连接最多一次重连、仅码率变化时复用 Decoder、Codec/FPS/尺寸变化时替换 Decoder、Negotiated Decoder Reset 后要求 Fresh Config，以及 Legacy Telemetry Prefix 和 Recovery Message Byte-for-byte 保持不变。

## Build Result

2026-07-14 已完成：

- Android `./gradlew --no-daemon clean test assembleDebug`：通过，61 个任务及全部 6 组 Self Test 成功。
- 全部 20 个 Mac Standalone Self Test：通过。
- `xcodegen generate`：通过。
- `OpenSidecarMac` macOS Debug Build（关闭 Code Signing）：通过。
- `OpenSidecariOS` Simulator Debug Build（关闭 Code Signing）：通过。

## Before/After Metrics

尚未完成同条件真机 A/B，因此本 PR 不声称 Frame Age 更低或吞吐提升。在当前 OnePlus OPD2413 上进行的短时 USB HEVC/120 验证中，首次 V2 `streamConfig` 到 `firstFrameRendered` 观察值为 191 ms，竞争连接接管后的新连接为 218 ms。这些是单次恢复观测，不是对比延迟结论。

## Known Risks

- Epoch 是进程内 Counter，不是加密或持久 Identity。
- 现有 1 MiB Legacy Frame Limit 未改变。
- Frame 仍使用 JSON Telemetry Prefix；Binary Header V2、Allocation 与 NAL Scan 优化属于后续阶段。
- 本 PR 报告 Decoder Low Latency Capability，但明确不启用 `KEY_LOW_LATENCY`。
- Timeout 值由确定性测试覆盖，但尚未使用真机数据调优。
- Simulator Build 证明源码兼容，不证明旧 TestFlight Receiver 的运行时行为。

## Pending Physical Validation

- Android WiFi HEVC 60/120 与 ADB USB HEVC 60 Negotiated Handshake；
- 更长的重复 Reconnect、Config Timeout 与 Stale-frame Injection 检查；
- 从设备日志确认 Stale-frame Rejection；
- 旧 OpenDisplay iOS Receiver 的 Video、Input、Ping/Pong 与 Reconnect；
- 同条件 Before/After Measurement。

## Completed Short Physical Checks

- 从设备 Loopback 直接抓取 Android Hello，确认 Protocol Version 2 和全部 6 项 Capability。
- 完成 ADB USB HEVC/120 的 Ack、Decoder Ready、First Frame 与 Streaming 状态链。
- 连续完成多个仅码率变化的 Config Version，未再销毁 MediaCodec，也未耗尽 Handshake Budget。
- 插入 1 秒竞争 Socket：Android 从 Generation 1 进入探针 Generation 2，随后接受 Mac Generation 3 并恢复 V2 Streaming；旧连接退出没有覆盖新状态。

## Next Step

PR 3 Keyframe/Drop Policy 与 PR 4 Frame-size Negotiation 已分别记录。下一实现阶段 PR 5 处理 MediaCodec Low-latency Selection 与 Fallback。MediaCodec Async、Binary Frame Header V2、Buffer Pool、UDP 和 QUIC 仍不在当前范围。

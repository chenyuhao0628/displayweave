[English](android-connection-generation.md) | [简体中文](android-connection-generation.zh-CN.md)

# Android Connection Generation

本文描述 [Android 稳定性与延迟审计](android-stability-latency-audit.zh-CN.md) 后实现的 PR 1 连接所有权模型。该模型适用于 Android WiFi 和 Per-device ADB Forward USB 共用的 TCP Listener，不改变旧 OpenDisplay Wire Format。

## 原问题

旧 Receiver 在同一个 Executor 上执行：

```text
accept -> 阻塞 readLoop -> Reader 退出 -> 下一次 accept
```

半断开的旧 Socket 因而可能阻止新 Mac 连接到达替换逻辑。Transport 回调没有连接身份，旧 Reader 晚到断开或旧 Writer 错误还可能清除全局 Connected、释放 Decoder，并停止较新的 Stream。

## 新所有权模型

Listener 现在拆分为三个执行角色：

```text
单一 Acceptor
    -> 原子安装 ConnectionContext(generation)
    -> 关闭旧 Socket
    -> 启动独立 Reader

单一 Writer
    -> 捕获请求的 Generation
    -> 仅当该 Generation 仍为 Current 时写入

Server Transport Event Executor
    -> 串行处理携带 Generation 的回调与状态迁移
```

每个 Accepted Connection 拥有不可变 Context：

- 单调递增的 `generation`；
- `Socket`、Buffered Input 和 Buffered Output；
- `connectedAtMs`；
- `lastPayloadAtMs`；
- Per-context Write Lock。

每个 Accepted Socket 同时启用 `TCP_NODELAY` 与 `SO_KEEPALIVE`。KeepAlive 只作为内核辅助信号，不能替代已有应用层 Ping/Pong 或后续 Connection Health 工作。

## Generation 规则

1. 各连接 Reader 独立阻塞，Acceptor 持续执行 `accept()`。
2. 新 Socket 到达时 Generation 加一，并原子成为 Current。
3. 替换完成后主动关闭旧 Socket。
4. Connected、Payload、Disconnected、Error 和 Writer Work 都携带 Generation。
5. 只有 `generation == currentGeneration` 才能：
   - 投递 Payload；
   - 发布 Connection State 或 UI Status；
   - 重置当前视频队列；
   - 释放当前 Decoder；
   - 停止当前 Streaming；
   - 发送 Control/Stats/Input 数据。
6. Stale Reader 退出只关闭自己的 Socket，不发布 Current Disconnect。
7. Stale Writer Failure 在关闭旧 Context 后被忽略，不能使新 Generation 失败。
8. Replacement 会退役旧 Decoder，并创建 Generation-bound Decoder Listener；旧 Decoder 晚到回调会被忽略。
9. 排队视频帧携带 Generation，进入 MediaCodec 前再次检查。
10. 只有一个 Writer Executor；Per-context Lock 还防止同步 Final `goodbye` 与普通 Write 重叠。

Generation 是进程内 Transport Identity，不是 Session Epoch、Config Version 或 Frame Sequence；后三者仍属于 PR 2 的协商协议工作。

## 应用层连接状态

PR 1 新增类型化 Snapshot：

```text
state
reason
enteredAtMs
generation
```

Enum 预留完整状态词汇，当前 Legacy Protocol 事件驱动以下可观测迁移：

```text
DISCONNECTED
    -> SOCKET_CONNECTED（接受 Current Generation）
    -> HELLO_SENT
    -> STREAM_CONFIG_RECEIVED
    -> DECODER_CONFIGURING
    -> DECODER_READY
    -> WAITING_FIRST_FRAME
    -> STREAMING（仅由第一帧 OnFrameRendered 回调触发）
```

已有 Decoder Stall Recovery 使用 `RECOVERING`。Current Generation Transport Error 在断开前记录为 `FAILED`。`HELLO_ACCEPTED` 与 `STREAM_CONFIG_ACCEPTED` 仅作预留；PR 2 增加协商 Ack 前，不声称它们已实现。

UI 不再把 Decoder 配置文本当成 Streaming 证据。只有 Current Generation 的首帧 Render Callback 才会启用 `STREAMING` 和可见 Streaming Panel。

## 兼容性

- 4 字节大端长度前缀不变。
- Legacy Hello、Ping/Pong、Stats、Input、Keyframe Request、Codec Fallback 和 Annex-B Video Payload 不变。
- 不发送 V2 Binary Header、Session Epoch、Config Version、Frame Sequence 或强制 Ack。
- Mac Sender 与旧 OpenDisplay iOS Receiver 协议不受 Android 内部回调改动影响。
- WiFi 与 Android ADB USB 继续进入同一个 Android TCP Listener。

## Modified Files

- `WifiTcpReceiverTransport.java`：独立 Acceptor/Reader、Connection Context、Socket Option、Current-generation Writer。
- `ReceiverTransport.java`：携带 Generation 的 Transport Contract。
- `ReceiverConnectionCoordinator.java`：Current Generation Guard 与类型化迁移。
- `ReceiverConnectionState.java` / `ReceiverConnectionStateSnapshot.java`：状态词汇与证据。
- `OpenDisplayServer.java`：串行 Transport Event、Generation-bound Queue/Decoder Callback、首帧 Streaming 迁移。
- `H264SurfaceDecoder.java`：MediaCodec Start 后显式 Decoder Ready Callback。
- `MainActivity.java`：用户可见状态映射和结构化 Generation Log。
- `ReceiverConnectionSelfTest.java` / `VideoStreamPolicySelfTest.java`：Stale Callback 与 Loopback Takeover 覆盖。

## Tests

自动测试覆盖：

- 新 Generation 后旧 Reader 晚到断开；
- Coordinator 拒绝旧 Writer Error；
- 第一条 Reader 仍阻塞时快速建立第二连接；
- 新连接主动关闭并替换阻塞旧 Socket；
- 只有 Current Generation 发布 Disconnect；
- 只有 Current Generation 写入和投递 Payload；
- 带 Generation/Reason 的状态 Snapshot；
- TCP_NODELAY 与 SO_KEEPALIVE；
- 所有已有 Android Protocol、Lifecycle、Stream Policy 和 Update Self Test。

## Build Result

2026-07-14 已完成并通过以下验证：

- Android `./gradlew --no-daemon clean test assembleDebug`：61 个任务完成，6 组 Self Test 全部通过，Debug APK 成功组装。
- Mac Policy/Self-test 可执行文件：20/20 通过。
- `xcodegen generate`：通过。
- `OpenSidecarMac` macOS Debug Build（关闭 Code Signing）：通过。
- `OpenSidecariOS` iOS Simulator Debug Build（关闭 Code Signing）：通过。
- Website/Docs 的 `pnpm build`、`pnpm run check:docs` 与 `pnpm run check:release`：通过。
- 全量测试后，Loopback Takeover Test 又连续顺序运行 20 次并全部通过。另一次同时启动 20 个 JVM 的尝试耗尽测试主机启动时间窗口，不作为产品测试结果。

以上结果只证明 Build 与确定性连接所有权行为，不能替代下列真机检查。

## Before/After Metrics

尚未完成同条件真机 Benchmark，因此不声称 Frame Age、Reconnect Time 或 Time To First Frame 已改善。Loopback 测试确定性证明的行为变化是：第一条 Connection 的 Read 仍阻塞时，第二连接仍可被接受。

## Known Risks

- PR 1 尚未实现 Application Payload Timeout 与 Video Health Timeout Policy。
- Session Epoch、Config Version、Frame Sequence 和 Ack 仍缺失。
- Android 入站单帧上限仍为 1 MiB。
- Drop Reason 和 Keyframe Coalescing 仍缺失。
- 新 `OpenDisplayServer` 实例会重置 Generation；这对进程内回调所有权是安全的，但不等同于跨进程 Session Identity。

## Pending Physical Validation

2026-07-14 执行 `adb devices -l` 未发现已连接 Android 设备，也没有可用的旧 OpenDisplay iOS Receiver/TestFlight 设备。因此以下项目均未标记为通过：

- WiFi 与 ADB USB HEVC 60/120 短时运行；
- 快速 Reconnect 和人为制造的半断开旧 Socket；
- USB 拔插、ADB Server 重启、授权撤销/恢复；
- Android 前后台与锁屏/解锁；
- 从 Log 核对 Current-generation 首帧状态和 Reconnect Timing；
- 旧 OpenDisplay iOS Receiver 的连接、视频与输入兼容。

## Next Step

PR 2 Capability Negotiation、Session Epoch、Config Version、StreamConfig Ack、Decoder Ready 与 First Frame Report 已实现，详见 [Android Protocol V2 协商](android-protocol-v2-negotiation.zh-CN.md)。进入 PR 3 前，仍需完成 PR 1 与 PR 2 的真机恢复和 Legacy iOS 检查。

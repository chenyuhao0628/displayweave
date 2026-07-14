[English](android-binary-frame-header-v2.md) | [简体中文](android-binary-frame-header-v2.zh-CN.md)

# Android Binary Frame Header V2 与分配路径

## Modified Files

- `Mac/BinaryFrameHeaderV2.swift`、`Mac/DeviceCapabilities.swift` 与 `Mac/MacSender.swift` 增加 Capability-gated Encoder 与 Legacy Fallback；
- Android Protocol/Frame Packet、Annex-B、Server、Decoder 与 Metrics 代码增加有界解析和零拷贝 Payload View；
- Protocol、Video-policy、Capability、Header 与 Benchmark Standalone Test 覆盖协议；
- Benchmark CSV/JSONL 和双语架构/索引文档发布新增证据。

## Purpose

PR 9 只在 Android Receiver 独立声明 `binaryFrameHeaderV2` 时替换每帧 JSON Telemetry Prefix。固定 Header 携带 Identity、Timestamp、Codec/Keyframe Flag 与 Payload Length，同时保留既有外层四字节 Length Prefix 和 Annex-B Codec Payload。

Legacy OpenDisplay iOS、旧 Android、不完整 V2 声明，以及仅支持完整 Core V2、但未声明独立能力的 Peer，继续使用既有 JSON Telemetry Prefix + Annex-B Bytes。不会仅因为 `protocolVersion` 为 2 就发送二进制 Header。

## Wire Contract

全部整数字段使用网络字节序。既有外层帧仍为 `[UInt32 length][payload]`；以下 52-byte Header 是协商后的 Android Payload Prefix：

| Offset | Bytes | Field |
| ---: | ---: | --- |
| 0 | 4 | Magic `DWV2`（`44 57 56 32`） |
| 4 | 1 | Version `2` |
| 5 | 1 | Flags |
| 6 | 2 | Header Length `52` |
| 8 | 8 | Session Epoch |
| 16 | 8 | Config Version |
| 24 | 8 | Frame Sequence |
| 32 | 8 | Capture Timestamp，Unix ms |
| 40 | 8 | Send Timestamp，Unix ms |
| 48 | 4 | Annex-B Payload Length |
| 52 | Variable | Annex-B Payload |

Flag 为 `KEYFRAME = 0x01`、`CODEC_CONFIG = 0x02`、`HEVC = 0x04` 与 `H264 = 0x08`，必须恰好设置一个 Codec Flag。未知 Version、未知/冲突 Flag、非正 Identity、错误 Header/Payload Length、截断及超过 16 MiB 绝对安全上限的 Payload，都会在进入 Decoder 前被拒绝。

## Capability 与兼容规则

- Android Hello 在六项 Core V2 Progress/Identity Capability 和 `maxFrameBytes` 之外，独立声明 `binaryFrameHeaderV2`；
- 只有 Peer 是 Android、Core V2 集合完整且存在独立 Binary Capability 时，Mac 才启用；
- Core Protocol V2 在没有本能力时仍可使用，并保留 JSON Telemetry Framing；
- 每个 VideoToolbox Encode 都绑定接收它的 Ready Connection Generation；断线期间或重连后才返回的 Callback 会在 Framing 前丢弃，因此旧 In-flight Output 不会进入新的 Android 或 Legacy iOS Session；
- Codec Flag 必须匹配已接受 StreamConfig；Identity Rejection 先于 Codec Rejection，使旧帧保留正确的 Stale Epoch/Version 原因。

## Allocation 与 NAL-scan 改动

- Android Length Reader 不再为四字节外层 Header 单独分配数组；
- `VideoFramePacket` 保留 Transport `byte[]`，以 Offset/Length View 传给 MediaCodec；剥离 JSON Telemetry 不再复制整帧；
- Binary Field 直接从 Byte 解析，避免每帧 JSON `String`；
- Decoder 配置完成后，Binary Flag 避免 Keyframe/Codec-config NAL Scan；
- Legacy Classification 使用一次 `NalSummary`，Decoder 配置复用该结果，只在 MediaCodec 真正需要 CSD 时复制 VPS/SPS/PPS；
- 仅错误日志使用的 NAL 描述以 Range 扫描，不再为每个 NAL 分配 List/`byte[]`。

Transport 仍会分配有界的外层 Payload Array。本 PR 不伪称已经实现 Reusable Transport Pool；`bufferPoolMiss` 会暴露该剩余工作。每窗口 `allocatedFrameBytes`、零拷贝 `bufferReuseCount`、`bufferPoolMiss`，以及 Android Runtime `gcCount`/`gcTimeMs` 会进入 Receiver Stats 与 Benchmark CSV/JSONL。

## Tests

- Failure-first Java Test 覆盖 Round Trip、Identity/Timestamp/Flag、未知 Version、错误 Header Length、冲突 Codec Flag、错误/超限 Payload Length、截断与 Legacy Fallback；
- Failure-first Swift Test 覆盖 Encoder/Decoder Round Trip 与无效 Version/Flag；
- Capability Test 证明 Legacy iOS、缺失/不完整声明不能启用，同时 Core V2 保持独立；
- Packet Test 证明 Binary/Legacy Payload 都保留原 Transport Array，并可观察 Codec Mismatch；
- NAL Test 证明一次 Summary 能通过 Source Range 报告参数集/Keyframe；
- Metrics Test 覆盖 Allocation/Reuse/Pool-miss 字段及稳定的 Benchmark Column/JSON。

## Build Result

- 聚焦 Android Protocol 与 VideoStream Policy Self Test：通过；
- 聚焦 Swift Binary Header、Device Capability 与 Benchmark Self Test：通过；
- Android Clean/Test/Debug Assembly：通过，`61 actionable tasks: 61 executed`；Protocol、Receiver Connection、Receiver Lifecycle、Update Policy、Update Verifier 与 Video Stream 六组 Self Test 全部通过；
- 22 个 Swift Standalone Self Test 全部通过，包含新增 Binary-header Round Trip 与 Legacy-fallback Contract；
- `xcodegen generate`、无签名 macOS Debug Build 与 Generic iOS Simulator Debug Build：通过；
- Production Site Build/Prerender、32 对双语文档、Release-link Validation 与 `git diff --check`：通过；
- `adb devices -l` 未发现已连接设备，所以下述真机矩阵仍为 Pending。

## Before/After Metrics

尚未采集同条件真机 A/B。本 PR 通过代码路径和测试证明减少软件复制/扫描，但不声称 Frame Age、GC Time 已下降或 Rendered FPS 已提高。新增计数器使后续主张可验证。

## Known Risks

- Flag 只会在本地 Capability Negotiation 后信任，并受边界/一致性校验；损坏 Annex-B 仍可由 Decoder Path 拒绝；
- 52-byte Inner Header 会轻微减少既有协商 Outer Frame Limit 下的可用编码 Payload；
- Transport Payload Allocation 仍存在；未来 Pool 必须明确 Latest-frame Replacement 与 Decoder Handoff 间的 Ownership/Release；
- Runtime GC Key 由平台提供；不可用时报告零，不伪造数据。

## Pending Physical Validation

- 使用协商 Header 完成 Android WiFi/ADB USB HEVC/H.264 连接；
- 确认 Ack、Decoder Ready、First Frame、Reconnect、Transport Switch 与 Stale-frame Rejection；
- 在同一 Scene 比较每窗口 `allocatedFrameBytes`、Reuse/Miss、GC Count/Time 增量、Frame Age P50/P95/P99、Rendered FPS 与 Decoder Drop；
- 复测旧 Android Build 和 Legacy OpenDisplay iOS Receiver，证明 Byte-for-byte Fallback。

实现期间没有连接实体 Receiver。

## Next Step

执行最终逐项兼容/恢复审计和当前可用的短时真机矩阵，不声称已完成延期的耐久或多设备覆盖。

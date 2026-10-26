[English](android-decoder-low-latency.md) | [简体中文](android-decoder-low-latency.zh-CN.md)

# Android MediaCodec 低延迟选择

本文记录 Android 稳定性/延迟工作的 PR 5。它增加 Capability-aware MediaCodec Selection 与有界 Low-latency Fallback，不改变 Transport、Queue Depth、Bitrate、Legacy iOS Protocol 或 MediaCodec Input Model。

## Purpose

PR 2 会报告 `createDecoderByType` 选中的 Decoder 及其是否声明 `FEATURE_LowLatency`，但从未设置 `KEY_LOW_LATENCY`；Vendor 拒绝该参数时也会让整个 Codec Path 失败。PR 5 将选择和回退变成显式策略，同时把“保留可工作的 Decoder”置于可选参数之上。

## Setting

Android **设置与帮助 → 解码器低延迟**提供：

- **自动**（默认）：优先选择明确报告 Low-latency Support 的硬件 Decoder，并请求启用；
- **开启**：作为明确用户选择执行相同的 Capability-gated 请求；
- **关闭**：绝不设置 `KEY_LOW_LATENCY`。

Auto 与 On 都遵守安全规则：仅在 API 30+ 且所选 Decoder 明确报告 `FEATURE_LowLatency` 时设置该 Key；On 不会强制注入不受支持的参数。修改设置会重建一次 Receiver Session，现有 Mac Reconnect Grace 仍然有限。

## Decoder Order and Fallback

Android 针对协商后的 Codec MIME 枚举 Decoder Candidate，并按以下顺序选择：

```text
Hardware Decoder
  -> Low-latency-capable Hardware Decoder 优先（Auto/On）
  -> 其他 Hardware Decoder
  -> Unknown Acceleration
  -> Software-only Decoder
```

此前已从 HEVC 声明中排除的 Known-broken HEVC Implementation 继续排除。Auto/On 下每个支持 Low Latency 的 Candidate 按以下顺序配置：

```text
同一 Decoder + KEY_LOW_LATENCY=1
  -> Configure/Start 失败：释放
  -> 同一 Decoder 不带 KEY_LOW_LATENCY 重试
  -> 下一 Decoder Candidate
  -> 所有 HEVC Candidate 均失败时沿用 Sender HEVC→H.264 Fallback
```

每次进入下一 Attempt 前都会释放失败的 Candidate 与 Callback Thread；Vendor `stop()`/`release()` 异常会被隔离。MediaCodec 工作继续运行于现有 Decoder Worker，串行 Network-event Executor 不等待 Codec Teardown。

## Runtime Evidence and Benchmark Fields

`decoderReady`、Receiver Stats 与 Mac CSV/JSONL Benchmark 现在记录：

- 请求的 `decoderLowLatencyMode`；
- 实际 `decoderName`；
- `hardwareAccelerated`、`softwareOnly` 与 Vendor 状态；
- `lowLatencySupported` 与 `lowLatencyEnabled`；
- `decoderConfigureSuccess` 与 `decoderFallbackReason`。

因此成功回退可以明确报告 support=true、enabled=false，并给出如 `lowLatencyConfigureFailed:CodecException` 的原因。所有 Candidate 耗尽时，会先记录 configureSuccess=false，再发送现有 Codec Failure/H.264 Fallback 消息。

## Modified Files

- Android Decoder、Runtime Info、Codec Capability Helper、Server、Settings UI、Receiver Stats，以及新的 Low-latency Mode/Selection Policy；
- Android Failure-first Policy/Protocol Test；
- Mac Receiver-stats Decoding 与 Benchmark Schema/Test；
- Android 和仓库双语文档。

## Tests

确定性测试覆盖 Auto/On/Off Parsing、默认 Auto、Hardware-first Ordering、Low-latency-capable Ordering、同一 Decoder Enabled/Disabled Attempt Order、Off Behavior、显式 Failed-runtime Metrics、扩展 `decoderReady` JSON、Receiver-stats JSON，以及稳定的 Benchmark CSV/JSONL Field。

## Build Result

- Android `clean test assembleDebug`：通过，61/61 Tasks 均执行；六组 Self-test 全部报告 PASS，Debug APK 成功组装。
- Mac Standalone Test：21/21 通过，包括 Decoder Benchmark 解码以及 CSV 列数稳定与表头唯一性检查。
- `xcodegen generate`：通过。
- 关闭签名的 macOS Debug Build：`BUILD SUCCEEDED`。
- 关闭签名的 Generic iOS Simulator Debug Build：`BUILD SUCCEEDED`，Legacy iOS 源码路径保持可构建。
- 网站 Production/SSR/Prerender Build：通过。
- 双语文档检查：通过，26 对。
- Release-link Check 与 `git diff --check`：通过。

## Before/After Metrics

尚未采集同条件真机 Off/On A/B，因此本 PR 不声称 Decode Latency 或 Frame Age 已降低。它提供进行该比较所需的实际 Mode 与 Decoder 证据。

## Known Risks

- Vendor Capability Advertisement 可能不准确，因此“不带 Low Latency 的重试”是必需行为；
- 本版本 Auto 与 On 有意采用相同的安全启用规则；On 表达用户意图，但不绕过 Capability Check；
- Decoder Selection 与失败回退仍需跨真实 Vendor Codec 的真机验证；
- 同步 `dequeueInputBuffer(0)` 策略保持不变，属于后续阶段。

## Pending Physical Validation

- 在同一 Android Device/Codec/FPS/Bitrate/Scene 下分别运行 Off 与 On；
- 比较 Rendered FPS、Frame Age P50/P95/P99、Decoder Drop 与 Decoder Error；
- 在 Benchmark 中核对实际 Decoder Name 与 Low-latency Flag；
- 在拒绝 `KEY_LOW_LATENCY` 的设备上证明 Same-decoder Fallback；
- 修改设置后重复短时 WiFi 与 ADB USB Recovery Check。

实现期间没有连接 Android 设备，因此不会从 Build Success 推断任何真机结果。

## Next Step

PR 6 现已单独实现 WiFi Low-latency Lock 与 Surface Frame-rate Lifecycle，见 [WiFi 低延迟 / Surface 帧率](android-wifi-low-latency-surface-frame-rate.zh-CN.md)。PR 7 应进入 Android Drop Classification 与 Adaptive-controller Filtering。

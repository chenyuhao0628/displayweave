[English](android-wifi-low-latency-surface-frame-rate.md) | [简体中文](android-wifi-low-latency-surface-frame-rate.zh-CN.md)

# Android WiFi 低延迟与 Surface 帧率

本文记录 Android 稳定性/延迟工作的 PR 6。它增加有界、考虑功耗的 WiFi Low-latency Lock Lifecycle，并补全现有 Surface Frame-rate Hint Lifecycle；不改变 Transport Protocol、Bitrate、Queue Depth、Codec 或 Legacy iOS Path。

## Purpose

Receiver 此前没有 `WIFI_MODE_FULL_LOW_LATENCY` Lock。Surface 已使用 API 30 两参数 `setFrameRate`，其平台实现默认 Only-if-seamless，但该 Hint 尚未形成完整 Lifecycle：停止/后台清理、Decoder 重建时显式重应用及 Benchmark 证据均缺失。

## WiFi Setting and Lifecycle

Android **设置与帮助 → WiFi 低延迟**提供“自动”（默认）、“开启”和“关闭”。本版本 Auto 与 On 使用相同的安全 Eligibility Rule。仅在 API 29+ 且以下条件全部成立时请求 Lock：

```text
实际 Transport = WiFi
+ App 前台
+ 已进入 Streaming
+ Surface 有效
```

Lock 使用 Non-reference-counted 模式，因此重复 State/Metrics Event 不会叠加 Acquire。USB/ADB Transport、Socket 断开或停止 Streaming、App 后台、Surface 销毁、设置 Off 与 Activity 销毁都会 Release。Acquire/Release Runtime Exception 被隔离并记录，不会让连接失败。Manifest 声明平台要求的 `WAKE_LOCK` Permission。

Android Framework 可以证明 App 持有 Lock，但 API 29 公共接口不能证明 Chipset-level Activation。因此 `wifiLowLatencyActive` 表示 App 持有 Lock 且应用层 Lifecycle 条件全部成立，不是伪造的 Radio Telemetry。

## Surface Frame-rate Lifecycle

请求的视频 FPS 会映射到不低于它的最小已支持显示刷新率；只有不存在更高模式时才向下回退，避免支持 60/120/165Hz 的设备把 90 FPS 错误映射为 60Hz。Window 与 Surface 使用 Fixed-source Compatibility。API 31+ 显式传入 `CHANGE_FRAME_RATE_ONLY_IF_SEAMLESS`；API 30 使用具有相同 Only-if-seamless 默认行为的两参数 Overload。

Surface 创建/改变、前台恢复、StreamConfig FPS 改变、Decoder 重建和 Streaming 开始时都会 Apply 或 Reapply。停止 Streaming、App 进入后台、Surface 销毁或 Activity 退出时，以 Frame Rate 0 清理。默认不请求 Non-seamless Switch。

UI 与 Benchmark 明确区分请求的视频 FPS、请求的 Surface FPS、Android 实际 Display Hz 与 Rendered FPS。

## Runtime and Benchmark Fields

Receiver Stats 与 Mac CSV/JSONL 记录：

- `requestedSurfaceFrameRate`、已有 `actualAndroidDisplayRefreshRate` 与 `frameRateApplyResult`；
- `wifiLowLatencyMode`、`wifiLowLatencyRequested`、`wifiLowLatencyAcquired`、`wifiLowLatencyActive` 与 `wifiLowLatencyReleaseReason`。

## Modified Files

- Android Manifest、Activity Lifecycle/Setting/Surface Integration、Server Listener/Stats 与新的 WiFi/Surface Lifecycle Class；
- Android Failure-first Lifecycle/Protocol Test；
- Mac Receiver-stats Decoding 与 Benchmark CSV/JSONL Schema/Test；
- Android 与仓库双语文档。

## Tests

确定性测试覆盖 Auto/On/Off 默认值、API Gate、WiFi Eligibility、USB Release、前后台 Release、重复 Acquire 防护、销毁清理、Surface Create/Config/Decoder/Streaming/Resume Reapply、幂等 Clear、Stats JSON 与稳定且唯一的 Benchmark Column。

## Build Result

- Android `clean test assembleDebug`：通过，61/61 Tasks 均执行；六组 Self-test 全部报告 PASS，Debug APK 成功组装。
- Mac Standalone Test：21/21 通过，包括新增 WiFi/Surface Field 的 CSV 列数稳定与表头唯一性检查。
- `xcodegen generate`：通过。
- 关闭签名的 macOS Debug Build：`BUILD SUCCEEDED`。
- 关闭签名的 Generic iOS Simulator Debug Build：`BUILD SUCCEEDED`，Legacy iOS 源码路径保持可构建。
- 网站 Production/SSR/Prerender Build：通过。
- 双语文档检查：通过，29 对带互链文档，包括 PR 4、PR 5 与 PR 6。
- Release-link Check 与 `git diff --check`：通过。

## Before/After Metrics

尚未采集同条件 WiFi Lock Off/On 或 Surface Hint A/B。本 PR 不声称 RTT 或 Frame Age 已降低，只提供有界控制以及进行有效比较所需的证据。

## Known Risks

- WiFi Lock 以功耗以及潜在吞吐/漫游行为换取调度延迟，因此 Auto 被严格限制在活跃 WiFi Streaming 期间；
- Lock Ownership 不证明 Vendor Firmware 已改变 Radio Scheduling；
- Surface Hint 是请求，系统可以继续使用其他刷新率；
- Reapply Path 已由确定性测试覆盖，但仍需真实 Activity/Surface/Vendor 验证。

## Pending Physical Validation

- 在同设备、同 Codec/FPS/Bitrate/Scene 下进行 WiFi Off/On 比较，记录 RTT P50/P95、Frame Age P50/P95/P99、Actual Bitrate、Rendered FPS 与 Drop；
- 验证切换 USB、断开、后台、Surface 丢失与 App 退出时 Lock 被释放；
- 在 60/90/120 配置间核对 Requested Surface FPS、Actual Display Hz、Rendered FPS 与 Apply Result；
- 检查视觉稳定性并确认没有 Non-seamless 黑屏切换；
- 重复短时 WiFi 与 ADB USB Recovery Check。

实现期间没有连接 Android 设备，因此不会从 Build Success 推断任何真机结果。

## Next Step

已由 [PR 7 Drop 原因策略](android-drop-reason-policy.zh-CN.md)实现。PR 8 应增加有界的 Mac 本地快速下降通道。

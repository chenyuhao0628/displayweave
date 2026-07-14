[English](android-quick-recovery-v2.md) | [简体中文](android-quick-recovery-v2.zh-CN.md)

# Android 快速恢复 V2 证据

## Modified Files

- 本证据矩阵汇总已实现的 Connection Generation、Protocol V2、Keyframe、Frame-size、Decoder、Transport 与恢复控制；
- 它取代当前 Android 稳定性/延迟构建所使用的旧简版通用清单。

## Purpose

定义精确的短时真机恢复流程，并将代码/测试证据与实体设备证据分开。本文不声称耐久或长期稳定性。

## 每个场景的必要结果

- 状态清晰且恢复有限；
- 旧连接不能更新 UI、释放当前 Decoder 或贡献 Frame；
- 无重复 Session、残留 ADB Forward、持续黑屏、无限 Queue 或 Retry Loop；
- 协商 Protocol V2 时，StreamConfig Ack、Decoder Ready、First Frame、Reconnect Time 与 Time To First Frame 可记录。

## Evidence Matrix

| Scenario | Code/Self-test Evidence | Physical Result |
| --- | --- | --- |
| USB 拔出 / 插回 | Generation Replacement、有限 Transport Recovery 与 Stale Callback Guard | 待测——无已连接设备 |
| ADB Server 重启 | Forward Reconciliation 与有限重试策略已覆盖 | 待测——无已连接设备 |
| 撤销 / 恢复 USB 授权 | 明确授权状态与有限恢复路径 | 待测——无已连接设备 |
| Android 后台 / 前台 | Surface 与 Receiver Lifecycle Self Test 通过 | 待测——无已连接设备 |
| Android 锁屏 / 解锁 | Surface Recreation 路径已覆盖 | 待测——无已连接设备 |
| WiFi 短暂断开 / 恢复 | Watchdog 与 Reconnect State Machine 有界 | 待测——无已连接设备 |
| Auto USB → WiFi | Install Identity 与 Single-current-session Policy 已实现 | 待测——无已连接设备 |
| Auto WiFi → USB | 新 Generation 在 Streaming 前替换旧连接 | 待测——无已连接设备 |
| HEVC → H.264 Fallback | Config Resend 与合并 Forced Keyframe 已实现 | 待测——无已连接设备 |
| 手动 Reconnect | Fresh Generation/Session Identity 与 Keyframe 已实现 | 待测——无已连接设备 |
| 快速连续 Reconnect | 忽略旧 Disconnect；仅 Current Generation 改变状态 | 待测——无已连接设备 |
| 旧连接半断开 / 新连接立即接管 | Accept Loop 与 Connection-generation Takeover Self Test 通过 | 待测——无已连接设备 |

## Test Procedure

每个可执行场景先预热 30 秒、正式记录 3 分钟，并至少重复两次（条件允许时三次）。记录 Transport、Codec、Requested FPS、Actual Display Hz、Rendered FPS Average/1% Low、Frame-age P50/P95/P99、RTT P50/P95、Bitrate、Queue、分类 Drop、Keyframe Count/Peak Size、Reconnect Time、Time To First Frame、Decoder Reset Count、Black-screen Count、Thermal/Power Metric 与视觉备注。

每次只改变一个主要变量。保留失败样本；出现不安全 Thermal 状态、Frame Age 持续增长或无界/重复恢复症状时停止。

## Tests

- Android Clean/Test/Assemble 与全部 Receiver Self-test Group 覆盖非实体状态机 Contract；
- Mac Standalone Test 覆盖 Transport Selection、ADB Forward、Keyframe Request、Queue Policy 与 Capability Fallback；
- 真机动作不能用 Mock 或 Source Inspection 冒充。

## Build Result

Android Clean/Test/Debug Assembly（61 个 Actionable Task 与六组 Self Test）、22 个 Swift Standalone Test、Xcode Generation、无签名 macOS/iOS Simulator Build、Production Site、34 对双语文档、Release Link 与 Diff Check 全部通过。本次审计的 `adb devices -l` 没有返回已连接设备。

## Before/After Metrics

目前没有真机恢复时间 Before/After。矩阵只记录已验证的软件 Contract，全部 Device Outcome 保持待测。

## Known Risks

- Vendor USB Authorization、ADB Daemon、WiFi、Surface 与 Codec 行为必须使用真机；
- Legacy iOS 兼容除了 Byte-for-byte Framing Test，还需要实际旧 Receiver Build；
- 短时恢复通过也不能证明 30 分钟或 2 小时耐久。

## Pending Physical Validation

上述十二个场景全部待测。当连接的 Panel 和 Decoder 确实支持时，还需运行 WiFi/USB HEVC 60/120 FPS。

## Next Step

连接当前可用 Android Receiver，执行矩阵并追加 Raw Run ID 与观察；没有证据时不得把 Pending 改成 Success。

[English](android-thermal-power-metrics.md) | [简体中文](android-thermal-power-metrics.zh-CN.md)

# Android 热状态与功耗指标

## Modified Files

- `AndroidPowerMetrics.java` 在不影响 Streaming 的前提下采样平台 Thermal、Power-saver 与 Sticky Battery 状态；
- Receiver Stats 与 Mac Benchmark Model 将读数写入 JSON、CSV 和 JSONL；
- Android 与 Swift Standalone Test 覆盖归一化、不可用值、解码及稳定导出列。

## Purpose

本阶段只增加测量能力，使 Thermal/Power 状态能与 Rendered FPS、Frame Age、Decoder Drop 和 GC 指标一起分析；不改变 Bitrate、Frame Rate、Scale、Codec 或恢复行为。

## Metrics

| Field | Source | Unavailable Behavior |
| --- | --- | --- |
| `thermalStatus` | Android 10+ 的 `PowerManager.getCurrentThermalStatus()` | `null` / `notAvailable` |
| `powerSaver` | `PowerManager.isPowerSaveMode()` | `null` / `notAvailable` |
| `batteryTemperature` | `ACTION_BATTERY_CHANGED`，0.1°C 转换为 °C | `null` / `notAvailable` |
| `batteryLevel` | Battery Level / Scale，百分比 | `null` / `notAvailable` |
| `charging` | Charging 或 Full 状态 | `null` / `notAvailable` |

采样在既有每秒 Stats Publication 中以 Best-effort 执行。Vendor/API Failure 与视频路径隔离；缺失数据不会被替换为 0 或 false。

Android Thermal Status 保留平台整数等级：None、Light、Moderate、Severe、Critical、Emergency 或 Shutdown。保留 Raw Value 便于后续关联变化，不在没有证据时引入自动策略。

## Tests

- 归一化测试证明 `365` 个 0.1°C 转换为 `36.5`°C，Battery Level 被限制为有效百分比；
- 不可用输入保持 `null`；
- Receiver Stats JSON 发布五个规范字段；
- Benchmark Decode、CSV Header 与 JSONL 保留全部五项读数。

## Build Result

- Android Clean/Test/Debug Assembly 通过，`61 actionable tasks: 61 executed`；六组 Receiver Self Test 全部通过；
- 22 个 Swift Standalone Self Test 全部通过；
- `xcodegen generate`、无签名 macOS Debug 与 Generic iOS Simulator Debug Build 通过；
- Production Site Build/Prerender、34 对双语文档、Release-link Validation 与 `git diff --check` 通过；
- `adb devices -l` 未发现已连接设备。

## Before/After Metrics

改动前，Benchmark 无法区分 Thermal/Power 状态变化与 Network/Decoder 退化。改动后该状态可以记录，但尚无同条件真机样本，因此不声称性能已经改善。

## Known Risks

- Thermal Status 要求 Android 10；更旧但受支持的 Android 版本会报告不可用；
- Sticky Battery Broadcast 与 Vendor Power Service 可能省略字段；
- Battery Temperature 是设备传感器读数，不等于环境温度或 SoC Junction Temperature；
- 相关性不等于因果，需要固定条件重复测试。

## Pending Physical Validation

- 在可用 Android Receiver 上检查 Idle、Streaming、Charging 与 Power Saver 状态的真实读数；
- 将变化与 Rendered FPS、Frame-age P50/P95/P99、Decoder Drop、GC 和 Bitrate 关联；
- 确认不支持或 Vendor 缺失的读数保持 `notAvailable`，而不是 0。

实现期间没有连接 Android 设备。

## Next Step

执行恢复与 Benchmark 指南中的短时 WiFi/USB 矩阵。在可重复证据出现前，不引入自动 `120 → 90 → 60` 或 Scale 降档。

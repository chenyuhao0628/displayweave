[English](README.md) | [简体中文](README.zh-CN.md)

# DisplayWeave 文档

## 当前用户指南

- [开发预览分发](development-preview.zh-CN.md)
- [`v0.2.0-preview.2` 发布说明](release-notes-v0.2.0-preview.2.zh-CN.md)
- [`v0.2.0-preview.3` 发布说明](release-notes-v0.2.0-preview.3.zh-CN.md)
- [发布检查清单](release-checklist.zh-CN.md)
- [Mac 与 Android 自动更新](automatic-updates.zh-CN.md)
- [稳定性与真机证据](stability-test-report.zh-CN.md)
- [性能指标审计](performance-metrics-audit.zh-CN.md)
- [Android 稳定性与延迟审计](android-stability-latency-audit.zh-CN.md)、[连接 Generation 模型](android-connection-generation.zh-CN.md)、[Protocol V2 协商](android-protocol-v2-negotiation.zh-CN.md)、[帧尺寸协商](frame-size-negotiation.zh-CN.md)、[Decoder 低延迟选择](android-decoder-low-latency.zh-CN.md)、[WiFi 低延迟 / Surface 帧率](android-wifi-low-latency-surface-frame-rate.zh-CN.md)与 [Drop 原因策略](android-drop-reason-policy.zh-CN.md)
- [短时 Benchmark 指南](benchmark-guide.zh-CN.md)
- [延迟测量](latency-measurement.zh-CN.md)
- [USB/WiFi Benchmark 规程](usb-vs-wifi-benchmark.zh-CN.md)
- [码率模式](bitrate-modes.zh-CN.md)、[自适应码率](adaptive-bitrate.zh-CN.md)、[本地快速拥塞下降](mac-local-fast-congestion-decrease.zh-CN.md)、[队列分析](low-latency-queue-analysis.zh-CN.md)与[关键帧策略](keyframe-strategy.zh-CN.md)
- [短时 USB/WiFi 证据](usb-vs-wifi-short-benchmark.zh-CN.md)、[快速恢复清单](quick-recovery-checklist.zh-CN.md)与[多设备架构审计](multi-device-architecture-audit.zh-CN.md)
- [路线图与验收](roadmap-and-acceptance.zh-CN.md)
- [Android 高刷新迁移证据](120hz-migration-plan.zh-CN.md)
- [品牌资源](brand-assets.zh-CN.md)与[品牌/文档审计](branding-and-doc-audit.zh-CN.md)

根目录指南包括[架构](../ARCHITECTURE.zh-CN.md)、[安全](../SECURITY.zh-CN.md)、[贡献说明](../CONTRIBUTING.zh-CN.md)和 [Android 接收端](../AndroidReceiver/README.zh-CN.md)。

## 历史/内部记录

[`v0.2.0-preview.1` 发布说明](release-notes-v0.2.0-preview.1.zh-CN.md)、
[Preview 0.1 / Preview 2 发布说明](release-notes-preview-0.1.zh-CN.md)、
`docs/superpowers/specs/`、`docs/superpowers/plans/` 及
`android-usb-transport-design.md` 记录既有版本或设计决策，可以保留原语言，
但不能作为唯一的当前用户说明。

## 状态词汇

- **已验证：** 在报告点名的硬件上实际执行。
- **实验性：** 已实现，但性能或兼容性依赖硬件。
- **待完成：** 尚未完成，也不会对外宣称已完成。

Preview 2 仍未完成双 Android 并发、同条件 USB/WiFi 受控 Benchmark，以及 30 分钟/2 小时耐久测试。

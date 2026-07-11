[English](120hz-migration-plan.md) | [简体中文](120hz-migration-plan.zh-CN.md)

# Android 高刷新迁移记录

Android 已实现 HEVC/H.265、H.264 回退和 30/60/90/120fps 协商。OnePlus OPD2413 在 HEVC/120 WiFi 历史测试中约 109–111 渲染 FPS并报告活动 120Hz 模式；Preview 2 又验证 USB HEVC/120 与 H.264/60 功能。请求 120fps、活动 120Hz 或编码 120 帧均不能替代接收端实际渲染 FPS。

结论必须联合观察 Mac capture/encode/send 与 Android receive/decode/render/queue/drop/latency。双 Android、同条件 USB/WiFi、30 分钟及 2 小时耐久仍待执行。英文原文保留逐轮历史日志，其中早期 WiFi-only/USB planned 只代表当时阶段。

后续报告必须记录设备、系统、分辨率、缩放、codec、码率、目标帧率、测试内容、温度、时长、p50/p95 延迟、渲染 FPS、drop 与队列，不得把目标值写成实测值。

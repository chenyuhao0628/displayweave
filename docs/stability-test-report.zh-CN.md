[English](stability-test-report.md) | [简体中文](stability-test-report.zh-CN.md)

# DisplayWeave Preview 0.1 稳定性测试报告

日期：2026-07-11。设备：OnePlus OPD2413 Android 平板、当前 DisplayWeave 0.1.0 iPhone、Mac 发送端。

## 通过

- Android USB HEVC/120 与 H.264/60 建流。
- Surface/前台返回、强停重开、ADB Server 重启、物理拔插、USB 授权取消/恢复后自动重连。
- 未授权状态不创建 forward 或高速重试；重新允许并回到 Receiver 后恢复。
- Auto 拔线后经过协议宽限与 0.5/1/2/4/8 秒恢复，约 26 秒切到同 install ID App WiFi；插线后原子升级 USB。
- USB 触摸和双指滚动回传 macOS。
- 当前 iPhone WiFi 与 Android 独立会话并发，Android 切换期间 iPhone 保持连接。
- 无线调试 ADB 端点不生成 USB forward，旧 forward 在拔线后清除。

## 未执行

- 两台 Android 同时连接。
- 同条件受控 USB/WiFi Benchmark。
- 30 分钟和 2 小时耐久测试（由维护者后续执行）。

本报告只陈述已观察行为，不把约 11 分钟非受控观察当作耐久或 Benchmark 结果。

[English](usb-vs-wifi-benchmark.md) | [简体中文](usb-vs-wifi-benchmark.zh-CN.md)

# Android USB 与 WiFi Benchmark 规程

状态：受控对比待执行。已有约 11 分钟 USB 观察因内容和配置变化，只属于功能证据。

## 固定条件

- 同一 Mac、Android、系统版本、室温与设备温度窗口。
- 同一虚拟分辨率/缩放、codec、码率、目标 FPS 与测试内容。
- USB 使用同一数据线/端口；WiFi 记录频段、AP、距离、RSSI 与其他流量。
- 每种传输至少预热 5 分钟，正式采样时长相同，交替顺序避免热偏差。

## 采集

记录 capture/encode/send/receive/decode/render FPS、p50/p95/p99 端到端延迟、queue、drop、码率、CPU/GPU、温度、功耗、断流与恢复次数。保存原始日志、配置和时间戳。

## 报告

分别列出 USB/WiFi 的中位数和尾延迟、稳定渲染 FPS、drop/queue、热衰减与恢复。只有差异大于测量噪声且多轮一致时才下结论。Preview 2 不预填“USB 更快”等未经测量结果。

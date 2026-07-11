[English](performance-metrics-audit.md) | [简体中文](performance-metrics-audit.zh-CN.md)

# DisplayWeave 性能指标审计

当前链路覆盖 capture、encode、send、receive、decode、render、queue、drop 与 latency。高刷新结论必须以 Android 实际渲染 FPS 为核心，并解释整个管线与温度；目标 120fps 和活动 120Hz 不能替代实测。

已知 OnePlus HEVC/120 WiFi 约 109–111 渲染 FPS。Preview 2 验证 USB HEVC/120 和 H.264/60 功能，但未完成同条件受控 USB/WiFi 数值对比，因此不发布未经记录的 USB 优势数字。

后续 Benchmark 固定分辨率、缩放、codec、码率、目标帧率、内容、温度起点和时长，至少报告 p50/p95 延迟、渲染 FPS、drop、队列、CPU/GPU/温度与恢复次数。

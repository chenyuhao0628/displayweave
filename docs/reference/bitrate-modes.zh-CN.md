[English](bitrate-modes.md) | [简体中文](bitrate-modes.zh-CN.md)

# 码率模式

Auto 是默认模式，会在 codec/传输边界内自适应。Manual 选择固定预设，并按实际链路限制。Benchmark 仅用于本地实验，可选择 10–200 Mbps，界面明确警告：Experimental、May increase latency、May cause queueing、For local benchmark only。

**v0.3.0 边界（2026-10-23）：** HEVC 局域网 12–100、HEVC USB 20–160、H.264 局域网 8–100、H.264 USB 10–100 Mbps。局域网包括以太网和 Wi-Fi，内部策略名仍为 `wifi`。preview.3 的 H.264 局域网上限是 60 Mbps；v0.3.0 允许直接手动选择 80/100 Mbps，无需 Benchmark 模式，参见[发布说明](../archive/releases/release-notes-v0.3.0.zh-CN.md)。Auto 的初始估算也区分传输；USB 使用更高的初始目标，例如 3040×1904、120fps、High、HEVC 约为 112 Mbps。设置界面根据已选 codec 和传输过滤 Manual 预设；发送端还会使用协商后的 codec 与实际传输再次校验。

v0.3.1（2026-10-26）将选择框标为“请求码率”。自动编码／传输列出可能适用的预设合集；显式选择会缩小列表。加载设置或切换模式时，无效预设在一次设置事务内归一到最近有效值。设备卡片解释协商编码／链路造成的限幅，并展示编码尺寸与 FPS。

Target Bitrate 表示编码器目标，Actual Bitrate 表示实测 socket 吞吐；两者在界面和记录中分开呈现。

放宽上限不等于强制 100 Mbps。3840×2160/60、H.264、清晰模式的 Auto 起始目标仍约 49.77 Mbps。如需请求 100 Mbps，选择 H.264 和“码率模式 → 手动 → 100 Mbps”。Mac 的本地恢复只在持续有视频活动且无拥塞后恢复原 Auto 目标，不会把健康的约 50 Mbps 会话自动提高到 100 Mbps。参见[源码审计与本机证据](../verification/mac-4k-latency.zh-CN.md)。

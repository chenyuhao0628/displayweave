# 码率模式

Auto 是默认模式，会在 codec/传输边界内自适应。Manual 选择固定预设，并按实际链路限制。Benchmark 仅用于本地实验，可选择 10–200 Mbps，界面明确警告：Experimental、May increase latency、May cause queueing、For local benchmark only。

边界为 HEVC WiFi 12–100、HEVC USB 20–160、H.264 WiFi 8–60、H.264 USB 10–100 Mbps。Auto 的初始估算也区分传输；USB 使用更高的初始目标，例如 3040×1904、120fps、High、HEVC 约为 112 Mbps。设置界面根据已选 codec 和传输过滤 Manual 预设；发送端还会使用协商后的 codec 与实际传输再次校验。

Target Bitrate 表示编码器目标，Actual Bitrate 表示实测 socket 吞吐；两者在界面和记录中分开呈现。

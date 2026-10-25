[English](adaptive-bitrate.md) | [简体中文](adaptive-bitrate.zh-CN.md)

# 自适应码率

DisplayWeave 提供 Auto、Manual、Benchmark 三种码率模式。Auto 从分辨率、FPS、codec 估算值开始，并受 codec/传输边界约束；Manual 使用边界内的固定预设；Benchmark 允许 10–200 Mbps，属于实验功能。

只有 Auto 自适应。在当前源码迭代（2026-10-26，尚未发布）中，拥塞在一秒降码率保持期后把目标降低 20%。低于初始目标时，连续健康三秒可提高 20%，直至恢复初始目标；高于初始目标的探测仍为每健康五秒提高 7%。默认独立升码率冷却为三秒，接收端采样间隔可能延长实际等待。局域网信号包括发送排队、连续 Android 队列深度、发送帧率缺口、帧龄上升、RTT 上升，以及连续两个窗口的已分类 Android 解码吞吐丢帧。Mac 捕获／编码丢帧只用于诊断，不再单独降码率或阻止恢复。USB 使用更严格的链路归因：Capture Skip、FPS 窗口错位、RTT 或 Frame Age 短时波动不会单独降码；真实 Pending Send 与 Android 解码压力仍然有效。Lifecycle、Stale Identity、Malformed Input、Transport 与 Codec Reconfiguration Drop 不会降低码率，也不会阻止 Stable Recovery。Legacy Android 汇总 Drop 继续用于观察，但不会被猜测为拥塞。Manual 与 Benchmark 不会自适应。参见 [Android Drop 原因策略](android-drop-reason-policy.zh-CN.md)。

运行时直接更新 VideoToolbox 的 `AverageBitRate` 与 `DataRateLimits`，随后重发 `streamConfig`，不会重建编码器。日志和 benchmark 数据会区分 Target/Actual Bitrate，并记录切换前后目标、原因和网络状态。

Mac 还会每 200 ms 采样本地发送压力。连续两个满队列或 Oldest-age 上升样本可以执行有界的 12% `localFastDecrease`。Local、Receiver 与 Stable-recovery Decision 共享一个 Decrease Hold 与 Decision Epoch；参见[本地快速拥塞下降](mac-local-fast-congestion-decrease.zh-CN.md)。

控制器和序列化路径已有自动测试；阈值成为最终结论前仍需实体设备拥塞与恢复测试。

# 自适应码率

DisplayWeave 提供 Auto、Manual、Benchmark 三种码率模式。Auto 从分辨率、FPS、codec 估算值开始，并受 codec/传输边界约束；Manual 使用边界内的固定预设；Benchmark 允许 10–200 Mbps，属于实验功能。

只有 Auto 会处理接收端统计。拥塞在一秒降码率保持期后把目标降低 20%；稳定五秒后可提高 7%，升码率另有独立五秒冷却。信号包括 Pending Send、Mac Drop、连续 Android Queue Depth、发送帧率缺口、Frame Age 上升、RTT 上升，以及连续两个窗口的已分类 Android Decoder Throughput Drop。Lifecycle、Stale Identity、Malformed Input、Transport 与 Codec Reconfiguration Drop 不会降低码率，也不会阻止 Stable Recovery。Legacy Android 汇总 Drop 继续用于观察，但不会被猜测为拥塞。Manual 与 Benchmark 不会自适应。参见 [Android Drop 原因策略](android-drop-reason-policy.zh-CN.md)。

运行时直接更新 VideoToolbox 的 `AverageBitRate` 与 `DataRateLimits`，随后重发 `streamConfig`，不会重建编码器。日志和 benchmark 数据会区分 Target/Actual Bitrate，并记录切换前后目标、原因和网络状态。

Mac 还会每 200 ms 采样本地发送压力。连续两个满队列或 Oldest-age 上升样本可以执行有界的 12% `localFastDecrease`。Local、Receiver 与 Stable-recovery Decision 共享一个 Decrease Hold 与 Decision Epoch；参见[本地快速拥塞下降](mac-local-fast-congestion-decrease.zh-CN.md)。

控制器和序列化路径已有自动测试；阈值成为最终结论前仍需实体设备拥塞与恢复测试。

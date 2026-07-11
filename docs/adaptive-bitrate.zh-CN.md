# 自适应码率

DisplayWeave 提供 Auto、Manual、Benchmark 三种码率模式。Auto 从分辨率、FPS、codec 估算值开始，并受 codec/传输边界约束；Manual 使用边界内的固定预设；Benchmark 允许 10–200 Mbps，属于实验功能。

只有 Auto 会处理接收端统计。拥塞在一秒降码率保持期后把目标降低 20%；稳定五秒后可提高 7%，升码率另有独立五秒冷却。信号包括 pending sends、Mac/Android 丢帧、连续 Android 队列、发送帧率缺口、Frame Age 上升和 RTT 上升。Manual 与 Benchmark 不会自适应。

运行时直接更新 VideoToolbox 的 `AverageBitRate` 与 `DataRateLimits`，随后重发 `streamConfig`，不会重建编码器。日志和 benchmark 数据会区分 Target/Actual Bitrate，并记录切换前后目标、原因和网络状态。

控制器和序列化路径已有自动测试；阈值成为最终结论前仍需实体设备拥塞与恢复测试。

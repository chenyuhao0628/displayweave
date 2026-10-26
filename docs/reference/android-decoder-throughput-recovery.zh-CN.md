[English](android-decoder-throughput-recovery.md) | 简体中文

# Android 解码吞吐与恢复

本次修改避免高刷新率 Android 视频流把暂时的编码或解码压力放大为数秒旧画面与参考帧损坏。

## 发送端背压

Mac 流水线预算现在同时统计 VideoToolbox 在途编码和 Network.framework 在途发送。此前只统计发送，因此异步编码器可能在 Socket 看似空闲时接收大量帧，随后集中输出大批过期数据。High、Balanced/Low、Gaming 仍分别使用 3、2、1 的预算，但预算覆盖整个编码到发送流水线。

## 解码能力与调度

Android 现在使用首选硬件解码器的 `VideoCapabilities` 限制 Hello 中上报的 `maxFps`。优先使用厂商发布的 PerformancePoint；没有 PerformancePoint 的设备回退到 `areSizeAndRateSupported`。屏幕刷新率仍是上限，不再被直接当作解码性能声明。

MediaCodec 输入和输出改用异步 Callback。Codec Input Buffer 可用前只保留一个最新待输入帧，替代原来的零超时 `dequeueInputBuffer(0)` 轮询。

## 参考链安全

如果已编码的预测帧在解码前被替换，Receiver 会标记参考链已断裂、请求关键帧，并在关键帧到达前拒绝依赖旧参考的普通帧。新增非拥塞 Drop 原因 `referenceChainBroken`；自适应码率控制器不得把它解释为网络拥塞。

## Surface 刷新率映射

没有精确显示模式时，Surface 现在选择不低于视频 FPS 的最小支持刷新率；只有不存在更高模式时才向下回退。因此在支持 60/120/165Hz 的设备上，90 FPS 视频会请求 120Hz，而不是 60Hz。

## 验证

- Android 策略、协议、生命周期、连接与更新自测通过；
- Android Debug APK 构建通过；
- Mac 发送队列自测覆盖编码与发送的组合压力。

仍需在同一设备和场景下进行 60/90/120 FPS 真机验证。必须记录待编码/待发送数、实际发送/接收/解码/渲染 FPS、Frame Age 分位数、`referenceChainBroken`、关键帧请求和视觉稳定性。

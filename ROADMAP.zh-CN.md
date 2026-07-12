[English](ROADMAP.md) | [简体中文](ROADMAP.zh-CN.md)

# DisplayWeave 路线图

## Preview 2 已交付并验证

- Android 每设备动态 ADB-forward USB。
- Auto 优先 USB、有限恢复、同 install ID WiFi 回退和 USB 重新升级。
- Android 前台/Surface 重连与 streamConfig 恢复。
- 在现有 OnePlus 真机验证 Android HEVC/120 与 H.264/60 USB。
- 已检查拔插、ADB 重启、取消/恢复授权、触摸和双指滚动。
- 离线 v2 签名 Android APK，以及当前 iPhone/Android 混合并发。
- 短时 benchmark 记录、Target/Actual Bitrate 分离、Auto/Manual/Benchmark、自适应码率、受限发送队列和传输感知关键帧（自动验证完成；实体性能矩阵待测）。

## 下一步验证

1. 两台 Android 同时连接，验证独立 serial、端口、清理、输入和重连。
2. 同分辨率、codec、码率条件下的 USB/WiFi 受控 Benchmark。
3. 由维护者执行 30 分钟和 2 小时耐久测试，记录温度、内存、重连与 forward 泄漏。
4. 扩大 Android SoC、macOS 版本、线缆和网络矩阵。

## 产品工作

- 加密 WiFi 配对与认证会话。
- iOS/iPadOS 高刷新链路和更广泛 Apple 真机验证。
- 稳定的公开协议版本与兼容性测试。
- 获得付费身份后提供 Developer ID 签名/公证与常规 iOS 分发。
- 最终透明/浅色/深色品牌母版与平台自适应图标。

高刷新目标在持续渲染帧证据达到定义阈值前保持实验状态。参见 [docs/roadmap-and-acceptance.zh-CN.md](docs/roadmap-and-acceptance.zh-CN.md)。

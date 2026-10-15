[English](ROADMAP.md) | [简体中文](ROADMAP.zh-CN.md)

# DisplayWeave 路线图

## 源码已完成 — 2026-10-16

- Mac 发送/接收角色互斥，局域网单向镜像/扩展。
- 统一 UI 规范及 Mac/iOS/Android/网站重构，可达的接收设置与双语响应式导航。
- 选择性迁入上游启动恢复、有界日志与双指误点击抑制。
- Apple 共用帧/游标边界、生命周期隔离、安全输入/几何转换、Android 控制消息背压。
- 32 组 Swift、六组 Android 自测、各平台构建，以及网站/iOS 模拟器检查。具体证据和缺口见[源码验收报告](docs/source-upgrade-audit-2026-10-16.zh-CN.md)。

这些源码变更不包含在公开的 v0.2.1-p6 产物中；发布准备仍需下列真机验收。

## Preview 2 已交付并验证

- Android 每设备动态 ADB-forward USB。
- Auto 优先 USB、有限恢复、同 install ID WiFi 回退和 USB 重新升级。
- Android 前台/Surface 重连与 streamConfig 恢复。
- 在现有 OnePlus 真机验证 Android HEVC/120 与 H.264/60 USB。
- 已检查拔插、ADB 重启、取消/恢复授权、触摸和双指滚动。
- 离线 v2 签名 Android APK，以及当前 iPhone/Android 混合并发。
- 短时 benchmark 记录、Target/Actual Bitrate 分离、Auto/Manual/Benchmark、自适应码率、受限发送队列和传输感知关键帧（自动验证完成；实体性能矩阵待测）。

## 下一步验证

先完成双 Mac 双方向、镜像/扩展、Wi-Fi/以太网、睡眠唤醒、显示器热插拔和 Intel 运行；在独立在线显示器下复核 Mac UI 与虚拟显示器清理，并完成 Android 视觉和移动端真实触摸验收。

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

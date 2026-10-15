[English](ARCHITECTURE.md) | [简体中文](ARCHITECTURE.zh-CN.md)

# DisplayWeave 系统架构

## 系统结构

DisplayWeave 由 macOS 发送端和 Apple/Android 接收端组成。Mac 使用 `CGVirtualDisplay` 创建虚拟显示器，经 ScreenCaptureKit 采集、VideoToolbox 编码，再通过本地直接 TCP 连接发送分帧视频；输入和接收端遥测沿同一会话返回。

每台已连接设备拥有独立的发送管线和 benchmark recorder。运行时码率切换直接更新 VideoToolbox 码率控制属性，不重建编码器。Auto 码率只消费当前会话的队列、丢帧、RTT 和 Frame Age 证据；发送队列与 GOP 策略分别受画质和传输方式约束。Target Bitrate 是配置意图，Actual Bitrate 是实测吞吐。

```text
macOS 虚拟显示器
  -> ScreenCaptureKit
  -> VideoToolbox H.264 / 协商后的 HEVC
  -> 分帧 TCP 会话
     -> Apple 接收端（usbmuxd USB 或 WiFi，H.264）
     -> Android 接收端（ADB-forward USB 或 WiFi，HEVC/H.264）
  <- 触摸、滚动、codec 状态、指标、生命周期消息
```

## 发现与身份

Apple 与 Android WiFi 接收端为兼容性继续广播 `_opensidecar._tcp` Bonjour/NSD 服务。install ID 用于跨传输识别同一应用安装实例。`OpenSidecar.xcodeproj`、bundle ID、Java 包名、偏好键和服务名属于迁移敏感的兼容契约，不代表当前对外品牌。

## Android USB

Mac 依次从显式偏好、`PATH`、Android SDK 环境变量、macOS 默认 SDK 和 Homebrew 查找 ADB；解析 `adb devices -l` 时，只允许状态为 `device` 且带有线 `usb:` 元数据的行，无线调试端点会被排除。

每个有线 serial 分配独立 loopback 端口：

```text
adb -s <serial> forward tcp:<动态本地端口> tcp:9000
```

每个 `DeviceSession` 只拥有和删除自己的映射，DisplayWeave 不使用 `adb forward --remove-all`。USB 复用正常的分帧协议、streamConfig、codec 协商、输入和指标链路。

## Auto 切换

Auto 优先 USB。故障后先经过协议级宽限，再执行 0.5/1/2/4/8 秒有限恢复；耗尽后只允许 install ID 相同的 WiFi 接收端。USB 恢复时，会先结束同 install ID 的 WiFi 会话，再连接 USB，避免单客户端 Android 接收端被两个 Mac 会话争抢。

## Codec 与帧率协商

旧 Apple 接收端使用 H.264。Android 广播 codec/刷新能力，接收 `streamConfig`，双方支持时优先 HEVC；codec 失败会回报控制消息并回退 H.264。Android 协商 30/60/90/120fps 目标并请求兼容显示模式；请求帧率不等于实际渲染帧率。

所有 Peer 都保留网络字节序的外层四字节帧长度。Legacy iOS 与未协商 Android Frame 使用 JSON Telemetry Prefix + Annex-B Payload。只有独立声明 `binaryFrameHeaderV2` 的 Android Peer 才会收到固定的 `DWV2` Identity/Timestamp/Flags Header；Receiver 随后把原始有界 Transport Array 的 Offset/Length View 交给 MediaCodec。详见 [Binary Header 与分配协议](docs/android-binary-frame-header-v2.zh-CN.md)。

## 生命周期与输入

Android 接收端在 9000 端口提供 TCP Server，渲染 Surface 返回时会幂等重启。重连时 Mac 先重发 streamConfig，再请求关键帧，并以收到对端协议消息而不是单纯 TCP connect 作为就绪条件。

触摸坐标、拖动状态、光标移动和双指滚动编码为控制 JSON，在 macOS 注入；输入注入需要辅助功能权限。

## 安全边界

- WiFi TCP 尚未生产级加密，只应在可信局域网使用。
- ADB RSA 授权会把 Mac 作为广泛调试主机信任，不只限 DisplayWeave。
- macOS Preview 使用 ad-hoc 签名且未公证。
- Android APK 使用保存在 Git 之外的项目离线密钥库。
- iOS 公开产物是未签名自签输入包。
- `CGVirtualDisplay` 是私有 API，可能随 macOS 版本变化。

参见 [SECURITY.zh-CN.md](SECURITY.zh-CN.md) 与 [docs/README.zh-CN.md](docs/README.zh-CN.md)。


## Mac 接收角色（开发构建）

Mac 应用可在发送和接收之间切换。接收角色先停止发送会话及发现任务，使用独立 TCP 监听、
有界分帧和 AVSampleBufferDisplayLayer 渲染 H.264。一次只接受一个发送端；旧连接回调
不能影响替代会话。发送端按接收屏幕逻辑点、缩放和 codec 尺寸/帧率上限配置。
Mac 使用 Apple legacy 帧，不启用 Android DWV2。详见[设计](docs/mac-to-mac-design.zh-CN.md)。

## 源码职责与有界任务（2026-10-16）

源码应用在同一 Wi-Fi 或以太网局域网支持互斥的 Mac 发送/接收角色；这是 v0.2.1-p6 下载之外的开发功能。镜像捕获现有显示器，扩展创建虚拟显示器。

| 区域 | 职责 |
| --- | --- |
| Mac 界面 | `OpenSidecarMacApp`、`MacRoleViews`、`SenderWorkspaceView`、`SenderSettingsView`、`SessionRow`、`UpdateViews`；`SettingsWindow` 只负责承载桌面设置窗口。 |
| Mac 会话 | `SenderController` 管理发现与替换屏障；每个 `DeviceSession` 拥有发送端和 `SessionLifetime`，启动失败或停止后的资源清理先于替换启动。 |
| iOS 界面 | `ReceiverScreen`、`ReceiverIdleView`、`ReceiverOnboardingView`、`ReceiverSettingsView`、`ReceiverPerformanceView`、`ReceiverModel`、`ReceiverVideoView`。 |
| Apple 共用边界 | `Shared/ReceiverFrameDecoder` 验证 legacy 帧长（最大 16 MiB）；`ReceiverCursorImage` 在解码前检查字节/像素几何；`BoundedLogWriter` 限制日志文件和排队任务。 |
| Android 界面 | `ReceiverUi` 管理公共样式，`ReceiverActivity` 管理连接/生命周期呈现。 |
| 网站 | 公共 CSS token 与语义 React 区块；服务端渲染和客户端 hydration 使用同一树，生成后检查双语页面。 |

`PhoneReceiver` 在串行队列维护监听/连接，忽略旧回调；进入后台先分离旧 socket，再尽力发送 goodbye。Android 控制写入限制为一个线程、128 个排队任务和 64 KiB 单条负载；读取限制为两个线程、两个排队任务。饱和时断开对应会话，避免输入无限积压。发送端在算术和 CoreGraphics 转换前验证几何与输入。

参见 [UI 规范](docs/ui-guidelines.zh-CN.md)、[开发命令](docs/development.zh-CN.md)与[源码验收和验证边界](docs/source-upgrade-audit-2026-10-16.zh-CN.md)。

[English](ARCHITECTURE.md) | [简体中文](ARCHITECTURE.zh-CN.md)

# DisplayWeave 系统架构

## 系统结构

DisplayWeave 由 macOS 发送端和 Apple/Android 接收端组成。Mac 使用 `CGVirtualDisplay` 创建虚拟显示器，经 ScreenCaptureKit 采集、VideoToolbox 编码，再通过本地直接 TCP 连接发送分帧视频；输入和接收端遥测沿同一会话返回。

每台已连接设备拥有独立的发送管线和 benchmark recorder。运行时码率切换直接更新 VideoToolbox 码率控制属性，不重建编码器。Auto 码率只消费当前会话的队列、丢帧、RTT 和 Frame Age 证据；发送队列与 GOP 策略分别受画质和传输方式约束。Target Bitrate 是配置意图，Actual Bitrate 是实测吞吐。

```text
macOS 虚拟显示器
  -> ScreenCaptureKit（视频 + 源码分支可选 48kHz 系统音频）
  -> VideoToolbox H.264 / 协商后的 HEVC
  -> 双向 TLS 内的 TCP 控制与回退分帧会话（明文需显式旧版兼容）
  -> 可选认证 udpMediaV1 Wi-Fi／局域网媒体、光标与音频通道（源码分支）
     -> iOS/iPadOS 接收端（usbmuxd USB 或 WiFi，协商 HEVC/H.264）
     -> Mac 接收端（局域网／固定直连接口，HEVC/H.264）
     -> Android 接收端（ADB-forward USB 或 WiFi，HEVC/H.264）
  <- 触摸、滚动、手写笔、经许可桌面输入、codec 状态、指标、生命周期消息
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

所有 Peer 都保留网络字节序的外层四字节帧长度。Legacy iOS 与未协商 Android Frame 使用 JSON Telemetry Prefix + Annex-B Payload。只有独立声明 `binaryFrameHeaderV2` 的 Android Peer 才会收到固定的 `DWV2` Identity/Timestamp/Flags Header；Receiver 随后把原始有界 Transport Array 的 Offset/Length View 交给 MediaCodec。详见 [Binary Header 与分配协议](docs/reference/android-binary-frame-header-v2.zh-CN.md)。

## 生命周期与输入

Android 接收端在 9000 端口提供 TCP Server，渲染 Surface 返回时会幂等重启。重连时 Mac 先重发 streamConfig，再请求关键帧，并以收到对端协议消息而不是单纯 TCP connect 作为就绪条件。

触摸坐标、拖动状态、光标移动和双指滚动编码为控制 JSON，在 macOS 注入；输入注入需要辅助功能权限。

## 安全边界

- v0.3.5 的 Apple 与 Android 默认使用固定证书指纹的双向 TLS 和显式邀请配对；旧版兼容需主动启用且仅限可信网络。详见[配对指南](docs/guides/secure-transport.zh-CN.md)。
- ADB RSA 授权会把 Mac 作为广泛调试主机信任，不只限 DisplayWeave。
- macOS v0.3.5 使用固定 Apple Development 身份，仍未公证；首次从临时签名迁移可能需要再授权，后续构建检查签名连续性。
- Android APK 使用保存在 Git 之外的项目离线密钥库。
- iOS 公开产物是未签名自签输入包。
- `CGVirtualDisplay` 是私有 API，可能随 macOS 版本变化。

参见 [SECURITY.zh-CN.md](SECURITY.zh-CN.md) 与 [docs/README.zh-CN.md](docs/README.zh-CN.md)。


## Mac 接收角色（实验性）

Mac 应用可在发送和接收之间切换。接收角色先停止发送会话及发现任务，使用独立 TCP 监听、
有界分帧和 AVSampleBufferDisplayLayer 渲染 H.264／经硬件能力确认的 HEVC。一次只接受一个发送端；旧连接回调
不能影响替代会话。发送端按接收屏幕逻辑点、缩放和 codec 尺寸/帧率上限配置。
Mac 使用 Apple legacy 帧，不启用 Android DWV2。详见[设计](docs/reference/mac-to-mac-design.zh-CN.md)。

## 源码职责与有界任务（2026-10-16）

源码应用在同一 Wi-Fi 或以太网局域网支持互斥的 Mac 发送/接收角色；v0.3.5 将其作为实验功能打包，实机验收仍待完成。镜像捕获现有显示器，扩展创建虚拟显示器。

| 区域 | 职责 |
| --- | --- |
| Mac 界面 | `OpenSidecarMacApp`、`MacRoleViews`、`SenderWorkspaceView`、`SenderSettingsView`、`SessionRow`、`UpdateViews`；`SettingsWindow` 只负责承载桌面设置窗口。 |
| Mac 会话 | `SenderController` 管理发现与替换屏障；每个 `DeviceSession` 拥有发送端和 `SessionLifetime`，启动失败或停止后的资源清理先于替换启动。 |
| iOS 界面 | `ReceiverScreen`、`ReceiverIdleView`、`ReceiverOnboardingView`、`ReceiverSettingsView`、`ReceiverPerformanceView`、`ReceiverModel`、`ReceiverVideoView`。 |
| Apple 共用边界 | `Shared/ReceiverFrameDecoder` 验证 legacy 帧长（最大 16 MiB）；`ReceiverCursorImage` 在解码前检查字节/像素几何；`BoundedLogWriter` 限制日志文件和排队任务。 |
| Android 界面 | `ReceiverUi` 管理公共样式，`MainActivity` 管理连接/生命周期呈现。 |
| 网站 | 公共 CSS token 与语义 React 区块；服务端渲染和客户端 hydration 使用同一树，生成后检查双语页面。 |

`PhoneReceiver` 在串行队列维护监听/连接，忽略旧回调；进入后台先分离旧 socket，再尽力发送 goodbye。Android 控制写入限制为一个线程、128 个排队任务和 64 KiB 单条负载；读取限制为两个线程、两个排队任务。饱和时断开对应会话，避免输入无限积压。发送端在算术和 CoreGraphics 转换前验证几何与输入。

参见 [UI 规范](docs/development/ui-guidelines.zh-CN.md)、[开发命令](docs/development/workflow.zh-CN.md)与[源码验收和验证边界](docs/archive/audits/source-upgrade-audit-2026-10-16.zh-CN.md)。

## HEVC、直连与 Pencil（源码迭代）

Mac HEVC 同时要求硬件编码器与接收端明确声明的硬件解码能力。`ReceiverVideoBitstream` 限制 NAL 数量和参数集大小；一次 codecFailure 请求限时 H.264 回退。HEVC 尺寸／帧率也满足某个完整 H.264 能力范围。非法 Mac 能力声明在采集前被拒绝。

`DirectCable` 仅分类链路本地有线**候选**，不认证设备或证明物理拓扑。选择候选后将 Bonjour 解析和 TCP 固定到同一接口。`DirectCableAutoConnectPolicy` 提供默认关闭的开关、每次出现一次尝试和手动断开抑制。正在等待 hello 的会话也按安装 ID 去重。

`pencil-v1` 通过 hello/inputConfig 显式协商。`PencilInputForwarder` 按整笔画保持原生／兼容协议；`PencilSample` 校验全部数值。`InputInjector` 发送 tablet point／proximity 并确定性取消。iOS `InputSendBudget` 在派发前限制最多 64 项排队／发送中的控制任务，每批不超过 64 KiB，连接代际隔离旧输入和完成回调。溢出关闭当前连接，由发送端释放按下状态。详见[协议与验收设计](docs/reference/hevc-wired-pencil-plan.zh-CN.md)。

## Apple 视频协商

两个 Apple 目标共用 `Shared/ReceiverVideoBitstream`。iOS 声明 `appleVideoV1` 编码/刷新范围；Mac 继续通过原设备身份识别。发送端在上限内协商最高 120fps、HEVC 和 H.264 回退，Android 保留独立 V2 协商。见[实现与证据](docs/guides/apple-video.zh-CN.md)。

## 已完成源码扩展

[功能台账](docs/archive/plans/feature-completion.zh-CN.md)记录桌面分辨率、默认认证传输、同意后的 Mac 键鼠回传、同身份 Mac 切换、Pencil v2 与具名快捷操作、进程 CPU 采样、Android 池化租借和共用协议样例。iOS 展示回调按视图身份归属：替换时先释放旧输入，旧视图延迟销毁不能清除新回调或移除借用图层。解码/展示回调带连接代次，跨线程帧回调加锁。真实正式签名与最终素材仍有外部前提。

## 桌面几何与实际编码负载（v0.3.2）

桌面逻辑点／底层像素与编码尺寸分别管理。iMac 档位与跟随接收端的几何保持所选布局，视频画质可独立适配。`EncoderWorkQueue` 把 VideoToolbox 所有权串行化并移出采集／控制队列，最多保留两次提交。`EncoderLoadController` 根据持续活动画面的编码压力判断，排除静止／网络受限窗口，遵循用户的分辨率／帧率优先选择。采集重配置清理缓存帧、拒绝过期代次并限制为五秒。详见[实施与证据](docs/verification/imac-resolution-performance.zh-CN.md)；在 v0.3.2–v0.3.5 发布包中，5K 桌面不扩展 4096×2304 的 Apple 视频解码范围（源码分支 `hevc5kV1` 已新增硬件门禁的 5120×2880@60 HEVC，见下文）。

## 桌面自动匹配（v0.3.3）

Mac 接收端的逻辑桌面根据可用的发送端参考屏和经过校验的系统报告物理尺寸估算。尺寸缺失时按比例回退；v0.3.3–v0.3.5 中移动接收端保留原有几何，已有偏好保持不变。屏幕变化按会话防抖，采用冷却和过期状态检查。v0.3.3–v0.3.5 发布包中 Apple 视频范围仍为 4096×2304，见[匹配证据](docs/verification/automatic-desktop-matching.zh-CN.md)。

## 高刷试验、解码器恢复与 Android 前台保活（v0.3.4 – v0.3.5）

Android 与符合条件的 iOS/iPadOS 接收端提供可选的原生分辨率高刷能力范围，不扩大默认保守上限。Android 端通过 `ReceiverKeepAliveService` 在活动会话期间提升为用户可停止的 `connectedDevice` 前台通知，并将停止命令排在前台提升确认之后，避免快速重连触发 `ForegroundServiceDidNotStartInTimeException`。`DecoderStallRecoveryPolicy` 在 V2 会话中请求新的 `streamConfig`（`streamConfigRequired`），在旧版 V1 会话（`!negotiatedV2`）中就地重建 `H264SurfaceDecoder`；`OpenDisplayServer.stop()` 与 `decoderWorker` 同步并在独立线程异步释放 `MediaCodec`。所有 `OpenDisplayServer.Listener`、`NsdAdvertiser.Listener` 与 `WifiTcpReceiverTransport` 回调均携带来源实例引用，防止旧实例异步回调污染当前 UI 状态。iOS/iPadOS 的 `MetalVideoRenderer` 在重置与代次切换间保护纹理提交并缓存 `MTKView.drawableSize`；Mac 接收端以解码出 `videoSize` 作为窗口展示与连接状态的门禁。详见 [v0.3.5 发布说明](docs/releases/v0.3.5.zh-CN.md)、[v0.3.4 发布说明](docs/releases/v0.3.4.zh-CN.md)与[Android 解码吞吐与恢复](docs/reference/android-decoder-throughput-recovery.zh-CN.md)。

## 低延迟媒体传输、`udpMediaV1` 与跨平台能力升级（源码迭代）

**已实现（源码分支，尚未包含在已发布下载产物中）：**
- **编码器 VBV、编码速度优先级与 TCP/UDP ABR 协同：** 运行时仅调整码率的 ABR 决策就地更新 VideoToolbox 速率控制属性（`AverageBitRate` 与 `50ms` `DataRateLimits` VBV 突发上限 `[max(ceil(bitrate / 8 * 0.05 * 1.5), 16_384), 0.05]`——即 `0.05s` 窗口内 `1.5x` 目标码率、最低 `16,384 B`），不发送新 `streamConfig` 也不重置接收端解码器。`AdaptiveBitrateController` 保持 `1.0s` 常规降码冷却，并在严重拥塞尖峰（`pendingSends >= 4`、`androidQueueDepth >= 4`、`androidCongestionDrops >= 3`、Wi-Fi `sentFps / encodedFps < 0.60`，或本机 `pendingSends > queueBudget`／`oldestPendingSendAgeMs >= 50`）时启用 `250ms`（`0.25s`）亚秒级快降冷却。当 `udpMediaSession.isReady` 激活时，TCP `AdaptiveBitrateController` 的降码裁决暂停，由 `UDPDelayGradientBWE` 驱动 `streamBitrate`（通过 `updateEncoderLoadCeiling` 叠加 `EncoderLoadController` 上限，且不以扣除 FEC 后的编码码率覆盖 pacer 的预 FEC 线速预算）；回退至 TCP 时由 `syncCurrentBitrate` 同步当前码率。发送端吞吐统计（`lastSentFps`、`lastActualBitrateMbps`、`onStats`）在 UDP 与 TCP 路径统一计量；iOS 接收端统计上报周期对齐为 `1.0s`（同时覆盖 Metal 与 `AVSampleBufferDisplayLayer` 路径的提交与背压延迟）。`CaptureFramePolicy` 在首帧编码后跳过无脏矩形（`dirtyRects`）的静态重复帧并保留 `500ms` 保活刷新，将 `SCStreamFrameInfo.displayTime` Mach 主机时间转换为采集时间戳，并为采集帧率上限更新增加 `5s` 超时保护。`StreamEncodingPolicy.prioritizesEncodingSpeed(quality:fps:)` 仅在 `quality == .smooth` 或 `fps >= 90` 时启用 `PrioritizeEncodingSpeedOverQuality`。Android 待解码队列收敛至 `4` 帧／`75ms`（`FrameQueuePolicy`），Apple 接收端（`PhoneReceiver` 与 `StreamReceiver`）接入 `ReceiverFrameAgePolicy`，在送入解码器前丢弃本机排队满 `65ms`（`0.065s`）或跨端同步帧龄满 `120ms` 的非关键帧 TCP 包。
- **认证的 `udpMediaV1` 媒体面（Wi-Fi／局域网）：** mTLS TCP 继续承载配对、控制、键鼠／手写笔输入、光标 PNG 位图、全部 USB 会话，以及默认保持内核 TCP 传输的固定有线 `DirectCable` 链路（`UDPMediaActivationPolicy`，可通过 `forceUDPMediaOnDirectCable` 覆盖；一旦在固定接口上创建 UDP 会话，均通过 `IP_BOUND_IF`／`IPV6_BOUND_IF` 绑定网卡并支持 IPv4/IPv6 双栈）。声明 `udpMediaV1` 的 Wi-Fi 与非固定局域网接收端协商建立会话级 UDP 通道（`UDPMediaProtocol`、`UDPMediaFEC`、`UDPMediaEngine`、`UDPMediaTransport`、`UDPDelayGradientBWE` 及 Android `UdpMediaProtocol`／`UdpMediaReceiverSession`）：`MacSender` 在 `streamConfig` 之后发送 `udpMediaConfig`（Apple 与 Android 接收端均按单调 `sessionEpoch` 接纳，首次连接无论先后均不会误拆活动 UDP 会话），接收端以 `150ms` 间隔发送最多 `6` 次初始 UDP 探测，就绪后若桌面静止则立即（`<20ms`）重编码 `lastPixelBuffer` 补发关键帧。每个数据包携带 16 字节头部作为 AES-128-GCM 的 AAD，配合 RFC 5869 HKDF-SHA256 双向会话密钥、64 位序列号翻转计数器（ROC）与 1024 包防重放滑动窗口。
- **Pacing、多块 FEC、NACK/RTX、抖动缓冲与延迟梯度 BWE：** `UDPDebtPacer` 按 `1.2x` 预 FEC 目标码率与 `1ms` 周期平滑发包（`maxQueuedPackets = 2048`），严格按 `cursor > audio > retransmit > keyframe > normalVideo > fecParity` 优先级调度，对光标执行最新值合并、限制最多 `16` 个排队音频包，并在新 IDR 到来时以 32 位回绕安全比较清理旧 P 帧分片。`UDPMediaFECEncoder` 基于 GF(256)（`0x11d`）按最多 `16` 块 × 每块 `<= 64` 数据分片（每块最多 `15` 个校验分片）生成 Cauchy/XOR Reed-Solomon 校验，并从编码器码率预算中扣除 FEC 冗余。接收端在校验分片先到时保持总分片数待定以避免多块大帧（`> 64` 分片）截断，数据分片齐备立即提交，缺包时经高斯消元恢复或发送乱序感知 NACK 位图（Android 接收端 `RTT <= 80ms`、单分片最多 `2` 次 NACK；发送端 `UDPRetransmitCache` 要求 `RTT <= 60ms`、缓存 `8` 帧／`512` 包／`80ms`、单分片最多重传 `1` 次），经 32 位回绕安全抖动缓冲保序输出（Apple `UDPJitterBuffer`：`3` 帧／`45ms`；Android `JitterBuffer`：`4` 帧／`35ms`，超时跨缺口时丢弃失参 P 帧直至下一关键帧），在动态改分辨率期间优雅忽略旧 `configVersion` 的 UDP 帧，并每 `30ms` 上报 `5ms` 突发到达梯度供 `UDPDelayGradientBWE`（`20` 样本 Trendline + AIMD）调速。活跃发送期间若接收端 UDP 静默超 `2.5s`，自动回退至 TCP 分帧并请求恢复关键帧。
- **认证 UDP 光标（`udpCursorV1`）、可选系统音频（`udpAudioV1`）、原生 5K HEVC（`hevc5kV1`）与 Display P3（`displayP3`）：** 声明 `udpCursorV1` 的接收端通过 UDP 接收 `125Hz` 归一化光标坐标（`packetType = 5`，17 字节大端载荷，单调 `sequence` 去重），光标 PNG 贴图仍走 TCP。发送端新增默认关闭的系统音频开关（`StreamSettings.audioEnabled`），与声明 `udpAudioV1` 的接收端配对开启后，由 ScreenCaptureKit 采集 `48kHz` 双声道系统音频（`excludesCurrentProcessAudio = true`），切分为 `5ms`（`240` 立体声采样帧 = `960 B`）S16LE PCM 数据包（`packetType = 6`，16 字节头 + `<= 1152 B` PCM），由 `MacAudioPlayer`、`IOSAudioPlayer` 与 Android `UdpAudioPlayer` 通过有界 `60ms`（`2,880` 帧）环形缓冲低延迟播放，并在断连、退后台或切换角色时立即停止。具备硬件 HEVC 解码能力的 Mac 接收端声明 `hevc5kV1`（同时接纳横竖屏 `4096×2304` 与 `5120×2880` 能力范围），仅在 HEVC 下协商最高 `5120×2880@60`（竖屏 `2880×5120@60`），H.264 回退时严格钳制回 `4096×2304`。Mac 与 iOS/iPadOS 接收端声明 `displayP3`，为 `SCStreamConfiguration`、`VTCompressionSession` 与 `MetalVideoRenderer` 标记 Display P3 色域参数（`P3_D65`／`sRGB`／`ITU_R_709_2`）。详见[协议规范修订版 2](docs/reference/protocol.zh-CN.md)。
- **跨平台手写笔／桌面输入、macOS 26.1 虚拟显示器物理尺寸下限与网络／证书诊断：** Android（`AndroidStylusInput`、`AndroidDesktopInput`）支持手写笔悬停／压感／倾角／橡皮擦（`pencil-v1`、TLS `pencil-v2`、`pencilAction`）及经 TLS 与双端许可的外接键鼠／触控板回传（`mac-input-v1` -> `desktopInput`）。iPadOS/iOS 将 `UIPointerInteraction` 悬停／点击／滚动与 `UIKeyboardHIDUsage` 硬件键盘接入经 TLS 许可的 `mac-input-v1`（`<= 16` 键并发上限、`⌃⌥Esc` 本地释放，失焦／退后台／断连发送 `releaseAll`），并通过 `WindowGeometryObserver` 对分屏（Split View）／台前调度（Stage Manager）／旋转窗口尺寸执行 `150ms` 防抖后更新 `hello`；`MacSender` 允许任意已认证 TLS 且声明 `mac-input-v1` 的接收端提交 `desktopInput`。`VirtualDisplayPhysicalSizePolicy` 将移动虚拟显示器默认物理尺寸从 `147×68 mm`（`~100 cm²`）提升至 `208×96 mm`（竖屏 `96×208 mm`，`~200 cm²`），避免 macOS 26.1 拒绝 `<160 cm²` 的虚拟显示器，并解析 Mac（接收端 `50...2000 mm` 非合成 `CGDisplayScreenSize`，发送端接受 `10...2000 mm`）、iOS/iPadOS（`50...2000 mm`）与 Android（`50...1000` DPI，`10...2000 mm`）上报的 `panel.millimetersWide`/`millimetersHigh`，按比例缩放以保证面积 `>= 20,000 mm²`（`200 cm²`）且单边 `<= 2,000 mm`。局域网／Bonjour TCP 连接设置 `NWParameters.preferNoProxies = true`（保留 `127.0.0.1`/`::1` 回环 ADB 与 usbmux 隧道不受影响）并监听 `NWConnection.viabilityUpdateHandler` 在拔线时即时收敛；`SenderController` 检测 macOS 本地网络权限拒绝（`kDNSServiceErr_PolicyDenied`，`-65570`），以 `1s..16s` 退避重试并展示中文恢复指引，在 Wi-Fi 推流且 `com.apple.sharingd` `DiscoverableMode` 为 `"Everyone"` 时给出非阻塞隔空投送（AWDL）信道扫描提示；Apple 与 Android TLS 存储均在 365 天传输证书过期时提示重置安全身份并重新配对。

**自动化验证：** 已由 `CaptureFramePolicySelfTest`、`UDPMediaProtocolSelfTest`、`UDPMediaFECSelfTest`、`UDPMediaEngineSelfTest`、`UDPDelayGradientBWESelfTest`、`UDPMediaTransportSelfTest`、`AdaptiveBitrateControllerSelfTest`、`StreamEncodingPolicySelfTest`、`ReceiverVideoFlowSelfTest`、`MacCoreUpgradeSelfTest`、`WireContractSelfTest`、`test-tls-interop.py` 及 Android `ProtocolSelfTest`、`WireContractSelfTest`、`VideoStreamPolicySelfTest` 覆盖。**实机验证：** 多设备 Wi-Fi 干扰、端到端 glass-to-glass 延迟、原生 5K HEVC 清晰度、UDP 系统音频音画同步及真机 Android/iPadOS 手写笔与外接键鼠体验仍属硬件依赖验收。

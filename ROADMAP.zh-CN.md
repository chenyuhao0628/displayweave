[English](ROADMAP.md) | [简体中文](ROADMAP.zh-CN.md)

# DisplayWeave 路线图

更新于 2026-11-15。当前已发布正式版本为 **v0.3.5（24）**（2026-11-10）；下方“源码分支已实现”章节列出的 `v0.3.5` 之后新增能力**尚未包含在已发布下载包中**。Mac 桌面匹配根据可用显示器数据估算尺寸，见[发布说明](docs/releases/v0.3.5.zh-CN.md)、[实施／验收台账](docs/verification/automatic-desktop-matching.zh-CN.md)与[协议规范修订版 3](docs/reference/protocol.zh-CN.md)。

## 当前 v0.3.5 正式版内容

- Android 旧版 V1 解码恢复与异步编解码器释放、iOS Metal 绘制尺寸／代次同步与旋转视频准入、Mac 接收端解码后窗口呈现门禁，以及有界 ADB/usbmux 管道与握手超时控制。
- 可选启用的 Android 实验性高帧率试验与前台保活服务、符合条件的 iPad 原生分辨率高刷试验，以及 Mac 圆角图标切片。
- 按会话隔离采集／编码恢复、健康队列码率恢复、有界 Apple／Android 解码背压、正确 Android 视频／输入比例和分辨率／帧率优先设置。
- Mac 4K 编码/光标延迟策略、有界接收背压、100 Mbps H.264 局域网预设和上游采集/显示器恢复，见[发布说明](docs/archive/releases/release-notes-v0.3.0.zh-CN.md)。
- 固定 Apple Development 签名与升级比较，本机已验证权限延续。
- 统一 UI 规范与主界面双向 OpenDisplay 兼容连接。
- 按设备自动匹配/跟随接收屏幕/1080p/1440p/4K/iMac 4K/4.5K/5K 桌面档位；有界编码队列与默认开启的实际负载适配保持窗口布局。
- Apple/Android 默认双向 TLS、邀请配对、撤销和显式旧版兼容。
- Apple HEVC/H.264 回退及有界 30–120fps 协商。
- 双端同意的 Mac 接收键鼠回传，焦点、角色和会话变化释放输入。
- 可选 Mac 有线/Wi-Fi 切换及同安装身份的有界恢复。
- Pencil roll/橡皮擦及经同意、由发送端定义的快捷操作。
- Mac 进程 CPU 指标与 Android 有界租借帧缓冲。
- 公开协议规范和 Swift/Java 共用样例。
- 仅 GitHub 发行规则、Apple 正式归档/导出预检工具、可复现 Android 自适应图标。

各项指南、检查和兼容边界见台账。目标 FPS 不等于实测渲染 FPS。

## 源码分支已实现（尚未包含在已发布下载包中）

- **免 ADB 的 Android `AOA 2.0` 有线 USB 与确定性 ADB 仲裁：** 用户态 Android Open Accessory（`0x18D1:0x2D00`/`0x2D01`）传输，支持 `.adb`/`.mtp` 接口门禁探测、`16 KiB` 批量 IN/OUT 传输与按包对齐 ZLP 及 `64` 次连续空读上限、默认双向 TLS（`UsbmuxTLSRelay` ↔ `LoopbackAccessoryBridge` + `SecureSocketAdmission`）、无锁序反转的 `UsbAccessoryReceiverTransport.Composite` USB↔Wi-Fi 切换、确定性 ADB 优先仲裁及 `0xE00002C5` 独占占用中文恢复提示，以及防止关闭授权弹窗后 AOA↔Wi-Fi 反复震荡的仅内存回退抑制。
- **认证 `udpMediaV1` 低延迟媒体平面、亚帧级 VBV 调速与静止高清刷新：** 基于 RFC 5869 HKDF-SHA256 + AES-128-GCM 的会话隔离 UDP 媒体平面，配备 16 字节 AAD 头部、1024 包 ROC 滑动防重放窗口、GF(256)（`0x11d`）系统码 Cauchy/XOR FEC（设置编码码率前先扣除 `5%`–`20%` 冗余开销）、选择性 NACK 重传、`1 ms` 优先级发包调度器、`NonBlockingUDPSocket` `EAGAIN` 帧完整性计量、接收端延迟梯度带宽估计（`UDPDelayGradientBWE`）、`2.5 s` 静默自动回退分帧 TCP、有界抖动缓冲（Apple `3` 帧 / `45 ms`、Android `4` 帧 / `35 ms`）、`50 ms`（`1.5×` 峰值、`16,384 B` 下限）VideoToolbox VBV `DataRateLimits`、运动停止后 `180 ms` 静止高清刷新帧（`MaxAllowedFrameQP = 20`，退出后安全恢复为 `51`）、`250 ms` TCP ABR 快速降码率保持、`65 ms` / `120 ms` TCP `ReceiverFrameAgePolicy`、`5 s` 采集／解码帧率重配置超时保护，以及 `smooth` 或 `>= 90 fps` 编码速度优先策略。
- **UDP 光标（`udpCursorV1`）、统一 UDP/TCP Opus 系统音频（`udpAudioV1`／`tcpAudioV1`／`audioOpusV1`）、音画同步、硬件门控 5K HEVC（`hevc5kV1`）与全链路 Display P3（`displayP3`）：** `125 Hz` 认证 UDP 归一化光标坐标（17 字节载荷；光标 PNG 贴图仍走 TCP）、默认关闭的可选 `48 kHz` 双声道系统音频（基于 Apple `AudioConverter` 与 Android `MediaCodec` 的 `20 ms` / `960` 帧 `128 kbps` Opus `formatFlags = 1` 编码与 `5 ms` / `960 B` S16LE 自动回退，覆盖 USB/DirectCable/TCP 回退的 `<= 4,096 B` `"audioFrame"` TCP 控制帧及 `pendingSends > 2` 即时丢弃保护、`120 ms` / `5,760` 帧环形缓冲上限，以及不受时钟偏移影响的 `15…90 ms` 音画同步水位与漂移裁剪）、Mac 硬件 HEVC `5120 × 2880 @ 60`（竖屏 `2880 × 5120 @ 60`）协商（H.264 回退严格封顶 `4096 × 2304`），以及 `CGVirtualDisplay` CIE 1931 Display P3 原色与 Apple/Android 广色域 `displayP3` 协商。
- **`panel` 物理毫米上报、完整 iPadOS 多任务窗口与跨平台手写笔／桌面输入：** Mac、iOS/iPadOS 与 Android 上报 `millimetersWide`/`millimetersHigh`，配合 macOS 26.1+ 移动端虚拟显示器 `208 × 96 mm` 默认值及等比放大保护（面积 `>= 20,000 mm²`、单边 `<= 2,000 mm`）；移除 `UIRequiresFullScreen` 并配置 `320 × 320` iPad 最小场景尺寸、去重 `150 ms` 防抖的 Split View / Slide Over / 台前调度窗口几何实时更新及旋转过渡期 `(w, h) == (cfgH, cfgW)` 接纳；iPadOS/iOS 与 Android 外接实体键盘/鼠标/触控板经双端同意复用 `mac-input-v1` 回传；Android 主动式手写笔支持 `pencil-v1` / `pencil-v2` / `pencilAction`。
- **直连抗干扰、局域网诊断、公证 DMG 与更新源防覆盖加固：** Mac 发送端局域网／Bonjour TCP 连接启用 `NWParameters.preferNoProxies = true`（经 `LANProxyBypassPolicy` 显式排除 `127.0.0.1`／`::1`／`localhost` 回环 ADB、AOA 与 usbmux 隧道），新增本地网络权限、AWDL 信道争用及保守 `8 s` 空 Wi-Fi AP 客户端隔离诊断，配对邀请按 Unicode 标量 UTF-8 字节安全截断，Android 构建禁用 `dependenciesInfo`，`tools/apple-distribution.py` 同时公证与 staple `DisplayWeave-macOS.dmg` 和 `DisplayWeave-macOS.zip`，GitHub Pages 部署自动叠加最新正式发行版的 `appcast.xml` 与 `android-update.json`（并校验 `SHA256SUMS.txt`），以及 20 项协议规范修订版 2/3 Swift/Java `udpMediaV1`／`tcpAudioV1`／`audioOpusV1` 确定性测试向量；详见[架构说明](ARCHITECTURE.zh-CN.md)与[协议契约](docs/reference/protocol.zh-CN.md)。

## 早期实现基线

本地 p8 产物包含 p7 的 Mac 收发局域网镜像/扩展预览、四端 UI 重构、选择性上游启动恢复、有界队列/帧协议、硬件条件下的 Mac HEVC、绑定接口的直连候选和基础 Pencil。更早预览验证过 Android 动态 ADB-forward USB、有界 USB/Wi-Fi 恢复及一个当前 iPhone/Android 并发。以带日期的发布说明和实机报告为准；历史证据不自动证明新加密传输表现。

## 外部前提

Apple 正式分发需要维护者的 Developer ID Application / Apple Distribution 身份、provisioning 和公证权限。工具已实现，真实正式签名/导出/公证仍阻塞。批准的可编辑/透明/深色/monochrome 品牌 master 与授权宣传截图也尚缺，继续使用现有位图衍生资源。

## 实机验收

双 Mac 自动匹配与原生 5K 清晰度、双向镜像/扩展、Wi-Fi/以太网/Thunderbolt Bridge 路由变化、睡眠唤醒、热插拔、Intel 运行、输入/键盘布局/快捷键；真实 Pencil 与 Android 主动式手写笔手势/旋转/橡皮擦与绘画软件；iPadOS 台前调度 / Split View / Slide Over 实时缩放及 iPadOS/Android 外接键盘/触控板/鼠标 `mac-input-v1` 体验；Apple/Android HEVC/Display P3/高刷显示；Android 免调试 `AOA 2.0` 热插拔、授权弹窗与 ADB 仲裁；`udpMediaV1` / `udpCursorV1` / `udpAudioV1` / `tcpAudioV1` / `audioOpusV1` 局域网/USB 抖动、丢包恢复、音画同步以及配对后的 LAN/USB 性能与重连。已发布 `v0.3.5` 下载包的 Apple 视频范围仍封顶为 `4096 × 2304` 且 Android USB 仅含 ADB 模式；源码分支硬件门控 `5120 × 2880 @ 60` HEVC（`hevc5kV1`）与 `AOA 2.0` USB 仍待真机验收。

还需双 Android 并发、相同分辨率/编码/码率的 USB/Wi-Fi 与 UDP/TCP 受控对比、30 分钟/2 小时耐久，以及更多 OS/SoC/线缆矩阵。虚拟显示测试必须具备独立在线显示器，见[验收要求](docs/archive/plans/roadmap-and-acceptance.zh-CN.md)。

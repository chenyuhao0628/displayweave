[English](apple-video.md) | [简体中文](apple-video.zh-CN.md)

# Apple 接收端 HEVC 与高刷新

v0.3.1 已包含：iOS/iPadOS 的 H.264 与硬件条件下的 HEVC，以及 Apple 接收端能力范围内最高 120fps 协商。实机高刷新性能尚未验证，见[发行证据](../releases/v0.3.1.zh-CN.md)。

v0.3.1 正式版（2026-10-26）新增“帧率上限 → 自动 / 30 / 60 / 90 / 120”和“分辨率优先 / 帧率优先”。分辨率优先先保留可用的最大编码尺寸，再选择帧率；帧率优先可缩小编码尺寸以达到所选上限，桌面逻辑布局保持不变。多个能力范围按所选优先级排序，不按总像素吞吐量排序。设备卡片显示编码像素、编码格式和协商目标。这些选项表达的是请求值。实际选择同时受接收屏幕、各编解码能力范围、用户选择和像素吞吐量约束（最多 4096×2304×60 像素/秒）。HEVC 的工作点必须也满足 H.264 回退，因此大尺寸可能只能协商 60 或 30 fps；降低编码画质后可能允许更高目标。声明的解码吞吐量是保守预算，不是实测性能结果。

两个 Apple 接收端共用有边界的 Annex-B 解析和格式创建。iOS 显式声明 `appleVideoV1`；旧端继续 H.264 和原帧格式。HEVC 需要双方硬件支持。解码失败只请求一次 H.264，整条连接保留回退结果，三秒内未收到回退则断开。非法/奇数尺寸、未知编码、超限 FPS 和参数集尺寸不匹配均拒绝；仅改变码率的配置不清空现有解码参考帧。

iOS 启用 `CADisableMinimumFrameDurationOnPhone`，连接期间设置 display link 的 `preferredFrameRateRange`。该 link 刷新光标，断连或视图离开窗口时停止。视频保持系统 sample-buffer layer 或原有可选 Metal 路径。真实刷新由 Core Animation 决定，低电量、温度和显示调度可降低刷新；接收 FPS 统计视频提交，不等于上屏。只有设备端现有 Metal presented 回调提供呈现时间，模拟器不能证明实机性能。

2026-10-26 源码还统一了 Apple 系统渲染层的有界背压：50 ms 内最多额外提交两帧，持续阻塞后清空一次并请求关键帧。iOS 增加独立的 15 秒首帧期限；只有心跳、没有视频的会话不能一直保持连接。已收到有效首帧的静态桌面不受此期限影响。本轮回归和模拟器证据见[升级记录](../verification/reliability-experience-upgrade.zh-CN.md)。

早期验证：39 个 Swift 套件（含 Apple 能力/配置/回退策略）、真实合成 H.264/HEVC 码流、Mac 回环高帧率配置/越界拒绝/编码回退、Mac universal Debug 与 iOS Simulator 构建。iPad 模拟器检查非法长度、替换连接、分片控制、能力/配置校验和合成码流回退。实机仍需固定尺寸/编码/码率测试 30/60/90/120 目标、两种渲染器、低电量/温度变化、旋转，以及 ProMotion 设备和高刷 Mac 屏幕持续上屏 FPS。

2026-10-16 核实的官方参考：[Apple：优化 iPhone/iPad 应用以支持 ProMotion](https://developer.apple.com/documentation/quartzcore/optimizing-iphone-and-ipad-apps-to-support-promotion-displays)，同时检查本机 SDK 的 `CADisplayLink.h` 与 VideoToolbox API。请求刷新率不保证真实屏幕节奏。

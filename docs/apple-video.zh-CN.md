[English](apple-video.md) | [简体中文](apple-video.zh-CN.md)

# Apple 接收端 HEVC 与高刷新

p8 之后的源码：iOS/iPadOS 新增 H.264 和硬件条件下的 HEVC，Apple 接收端最高可协商 120 fps。已发布 p8 仍使用原 iOS H.264 链路和 Mac 60 fps 上限；本次源码功能尚未发行，也未覆盖用户的 Mac 安装。

Mac 发送端“帧率 → 自动 / 60 / 90 / 120”是请求值。实际选择同时受接收屏幕、各编解码能力范围、用户选择和像素吞吐量约束（最多 4096×2304×60 像素/秒）。HEVC 的工作点必须也满足 H.264 回退，因此大尺寸可能只能协商 60 或 30 fps；降低编码画质后可能允许更高目标。声明的解码吞吐量是保守预算，不是实测性能结果。

两个 Apple 接收端共用有边界的 Annex-B 解析和格式创建。iOS 显式声明 `appleVideoV1`；旧端继续 H.264 和原帧格式。HEVC 需要双方硬件支持。解码失败只请求一次 H.264，整条连接保留回退结果，三秒内未收到回退则断开。非法/奇数尺寸、未知编码、超限 FPS 和参数集尺寸不匹配均拒绝；仅改变码率的配置不清空现有解码参考帧。

iOS 启用 `CADisableMinimumFrameDurationOnPhone`，连接期间设置 display link 的 `preferredFrameRateRange`。该 link 刷新光标，断连或视图离开窗口时停止。视频保持系统 sample-buffer layer 或原有可选 Metal 路径。真实刷新由 Core Animation 决定，低电量、温度和显示调度可降低刷新；接收 FPS 统计视频提交，不等于上屏。只有设备端现有 Metal presented 回调提供呈现时间，模拟器不能证明实机性能。

验证：39 个 Swift 套件（含 Apple 能力/配置/回退策略）、真实合成 H.264/HEVC 码流、Mac 回环高帧率配置/越界拒绝/编码回退、Mac universal Debug 与 iOS Simulator 构建。iPad 模拟器检查非法长度、替换连接、分片控制、能力/配置校验和合成码流回退。实机仍需固定尺寸/编码/码率测试 30/60/90/120 目标、两种渲染器、低电量/温度变化、旋转，以及 ProMotion 设备和高刷 Mac 屏幕持续上屏 FPS。

2026-10-16 核实的官方参考：[Apple：优化 iPhone/iPad 应用以支持 ProMotion](https://developer.apple.com/documentation/quartzcore/optimizing-iphone-and-ipad-apps-to-support-promotion-displays)，同时检查本机 SDK 的 `CADisplayLink.h` 与 VideoToolbox API。请求刷新率不保证真实屏幕节奏。

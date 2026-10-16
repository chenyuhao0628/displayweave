[English](release-notes-v0.2.1-p7.md) | [简体中文](release-notes-v0.2.1-p7.zh-CN.md)

# DisplayWeave `v0.2.1-p7` 发布说明

版本 `0.2.1-p7`，Mac 构建号／Android version code 为 `14`。本开发预览版打包 PR #11、#12 已审查的 Mac 互联、UI 和输入改进；新增硬件相关功能仍属实验性。

## 变更

- 任一 Mac 都可发送或接收，通过 Wi-Fi／以太网每次单向扩展或镜像；双方需 macOS 14+，发送与接收角色互斥。
- Mac 视频协商硬件 HEVC，保留 H.264 回退、保守尺寸限制与最高 60 fps；同一连接重配置后仍保持回退结果。
- 有线链路本地 Mac 发现会标记直连候选，Bonjour／TCP 固定到对应接口。自动连接默认关闭；普通 USB-C 线不代表已建立 Mac 网络。本版本不含远程关机。
- iPad Pencil 协商压感、倾角和支持的悬停，包含防手掌干扰、有界输入队列及确定性取消。旧发送端按整笔画保持触控兼容；iOS 视频仍为 H.264。
- Mac、iOS、Android 和网站落实统一 UI 规范，改善接收设置、导航及失败／重试状态。
- 加固会话清理、旧回调隔离、帧／游标边界、日志上限和 Android 输入背压；USB／局域网模式变化会阻止不允许的重连。

画质通过重建会话改变编码缩放（50%／75%／100%，流畅 75%），没有新增逐设备固定 1080p／1440p／4K 桌面模式选择器。

## 验证与待完成验收

源码已通过 37 组 Swift、Mac arm64/x86_64 构建、iOS 模拟器构建、Android 测试／构建、网站与双语文档检查。发行工作流另行构建并验证分发包、Android 签名和更新元数据；打包后记录实际产物哈希及工作流证据。

双 Mac 实际路由／性能、真实 Pencil 压感／倾角／悬停／防误触、新 UIKit 手势运行、Intel 运行及 30 分钟／2 小时耐久验收仍待完成。主机未确认独立显示器在线，因此跳过虚拟显示器交互；自动检查和编码样本解析不代表实测上屏性能。参见[功能指南](hevc-wired-pencil.zh-CN.md)。

## 分发与升级

继续提供七项产物：Mac DMG、Sparkle ZIP、Android APK、未签名 iOS 自签输入包、`appcast.xml`、`android-update.json` 和 `SHA256SUMS.txt`。Mac 仍采用 ad-hoc 签名且未公证；APK 保持固定项目证书；iOS IPA 需个人重新签名才能安装。应用 ID 和更新公钥保持不变。

Android p6 及以后优先使用 Cloudflare，只在可用性失败时回退 GitHub；p5 及更早版本需手动安装一次以信任镜像。发布后，已支持更新渠道的 Mac／Android 安装可通过原渠道升级。

[GitHub Release](https://github.com/chenyuhao0628/displayweave/releases/tag/v0.2.1-p7)

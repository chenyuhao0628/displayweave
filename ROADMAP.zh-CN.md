[English](ROADMAP.md) | [简体中文](ROADMAP.zh-CN.md)

# DisplayWeave 路线图

更新于 2026-10-26。当前版本为 **v0.3.1（20）**。采集／编码恢复、拥塞后画质恢复、Android 视频／触控比例和更清晰的设置已完成，见[发布说明](docs/releases/v0.3.1.zh-CN.md)与[实施／验收台账](docs/verification/reliability-experience-upgrade.zh-CN.md)。目录和文档整理属于源码维护，不改变已发布二进制。

## 当前 v0.3.1 正式版内容

- 按会话隔离采集／编码恢复、健康队列码率恢复、有界 Apple／Android 解码背压、正确 Android 视频／输入比例和分辨率／帧率优先设置。
- Mac 4K 编码/光标延迟策略、有界接收背压、100 Mbps H.264 局域网预设和上游采集/显示器恢复，见[发布说明](docs/archive/releases/release-notes-v0.3.0.zh-CN.md)。
- 固定 Apple Development 签名与升级比较，本机已验证权限延续。
- 统一 UI 规范与主界面双向 OpenDisplay 兼容连接。
- 按设备 Native/1080p/1440p/4K 扩展桌面分辨率。
- Apple/Android 默认双向 TLS、邀请配对、撤销和显式旧版兼容。
- Apple HEVC/H.264 回退及有界 30–120fps 协商。
- 双端同意的 Mac 接收键鼠回传，焦点、角色和会话变化释放输入。
- 可选 Mac 有线/Wi-Fi 切换及同安装身份的有界恢复。
- Pencil roll/橡皮擦及经同意、由发送端定义的快捷操作。
- Mac 进程 CPU 指标与 Android 有界租借帧缓冲。
- 公开协议规范和 Swift/Java 共用样例。
- 仅 GitHub 发行规则、Apple 正式归档/导出预检工具、可复现 Android 自适应图标。

各项指南、检查和兼容边界见台账。目标 FPS 不等于实测渲染 FPS。

## 早期实现基线

本地 p8 产物包含 p7 的 Mac 收发局域网镜像/扩展预览、四端 UI 重构、选择性上游启动恢复、有界队列/帧协议、硬件条件下的 Mac HEVC、绑定接口的直连候选和基础 Pencil。更早预览验证过 Android 动态 ADB-forward USB、有界 USB/Wi-Fi 恢复及一个当前 iPhone/Android 并发。以带日期的发布说明和实机报告为准；历史证据不自动证明新加密传输表现。

## 外部前提

Apple 正式分发需要维护者的 Developer ID Application / Apple Distribution 身份、provisioning 和公证权限。工具已实现，真实正式签名/导出/公证仍阻塞。批准的可编辑/透明/深色/monochrome 品牌 master 与授权宣传截图也尚缺，继续使用现有位图衍生资源。

## 实机验收

双 Mac 双向镜像/扩展、Wi-Fi/以太网/Thunderbolt Bridge 路由变化、睡眠唤醒、热插拔、Intel 运行、输入/键盘布局/快捷键；真实 Pencil 手势/旋转/橡皮擦与绘画软件；Apple HEVC/高刷显示；配对后的 LAN/USB 性能与重连。

还需双 Android 并发、相同分辨率/编码/码率的 USB/Wi-Fi 受控对比、30 分钟/2 小时耐久，以及更多 OS/SoC/线缆矩阵。虚拟显示测试必须具备独立在线显示器，见[验收要求](docs/archive/plans/roadmap-and-acceptance.zh-CN.md)。

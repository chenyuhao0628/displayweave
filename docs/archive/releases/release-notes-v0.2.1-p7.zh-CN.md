[English](release-notes-v0.2.1-p7.md) | [简体中文](release-notes-v0.2.1-p7.zh-CN.md)

> 历史记录：保留撰写时的版本、命令和结论，不作为当前操作指南。当前入口见[文档导航](../../README.zh-CN.md)。

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

源码已通过 37 组 Swift、Mac arm64/x86_64 构建、iOS 模拟器构建、Android 测试／构建、网站与双语文档检查。发行工作流另行构建并验证分发包、Android 签名和更新元数据；Release run [38839071173](https://github.com/chenyuhao0628/displayweave/actions/runs/38839071173) 在 tag 提交 `e56250c4539dcd8449508265401b4f28dddf1ccd` 成功，准备镜像期间有意跳过更新源部署。下载后的产物独立通过 `verify-update-release.sh`：Mac DMG／ZIP 身份与签名一致，Android 版本／证书及六项哈希均正确。Mac 可执行文件包含 arm64 和 x86_64；iOS 输入包为未签名 arm64，两者均为 `0.2.1-p7 (14)`。另使用 CryptoKit 和内置 Sparkle 公钥独立验证了 ZIP 的 Ed25519 签名。

双 Mac 实际路由／性能、真实 Pencil 压感／倾角／悬停／防误触、新 UIKit 手势运行、Intel 运行及 30 分钟／2 小时耐久验收仍待完成。主机未确认独立显示器在线，因此跳过虚拟显示器交互；自动检查和编码样本解析不代表实测上屏性能。参见[功能指南](../../guides/hevc-wired-pencil.zh-CN.md)。

## 分发与升级

继续提供七项产物：Mac DMG、Sparkle ZIP、Android APK、未签名 iOS 自签输入包、`appcast.xml`、`android-update.json` 和 `SHA256SUMS.txt`。Mac 仍采用 ad-hoc 签名且未公证；APK 保持固定项目证书；iOS IPA 需个人重新签名才能安装。应用 ID 和更新公钥保持不变。

Android p6 及以后从对应的 GitHub Release 下载；p5 及更早版本需手动安装一次。发布后，已支持更新渠道的 Mac／Android 安装可通过原渠道升级。

[GitHub Release](https://github.com/chenyuhao0628/displayweave/releases)

## 产物完整性

| 产物 | SHA-256 |
| --- | --- |
| `DisplayWeave-Android.apk` | `ac1b5081259647c248e8c5d69aff4f477f4ebc9044a70c4a4602f6c81d6c2381` |
| `DisplayWeave-macOS.zip` | `dae40c3df8f9bbdebdce0484621a7d7a6a4c99c1b1a8504e9096fc8863705aef` |
| `DisplayWeave-macOS.dmg` | `26e9cf259410e731acfbe1a682444b71bf73d679298db6b00d82b3bef15ce0f6` |
| `DisplayWeave-Preview-0.1-iOS-unsigned-resigning-input.ipa` | `634305344f5cd7433a74a95166f781ea7313d5473ded88918528a3895e8eb1eb` |
| `appcast.xml` | `6b56809092184de9bc4043667f4e6fc9e0b293e8689b1e9c1c67c9be2c30a8b1` |
| `android-update.json` | `3486c40d0a72cb3fc4acdfedcbe2299d01f90bdd67432f8a32003e24d3091a50` |

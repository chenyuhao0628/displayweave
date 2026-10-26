[English](release-notes-v0.3.0-preview.3.md) | [简体中文](release-notes-v0.3.0-preview.3.zh-CN.md)

> 历史记录：保留撰写时的版本、命令和结论，不作为当前操作指南。当前入口见[文档导航](../../README.zh-CN.md)。

# DisplayWeave v0.3.0-preview.3

发行日期：2026-10-17（Asia/Shanghai）。Mac build／Android version code：**18**。原生／签名基线：`92b5834`，包含 PR #16。本版保留 preview.2 的 UI 与 OpenDisplay 兼容，修复 Mac 构建和签名流程。

## 改动

- Mac 预览构建使用固定 Apple Development 身份。Run 和打包流程在身份缺失或变化时停止，不会静默回退临时签名。
- 更新打包与上一份已发布应用比较真实身份要求、团队、bundle 身份和架构。Debug 保留独立 bundle ID，验证 hardened runtime、正常的空 Release entitlements 和已签名 Sparkle。
- 更新中英文安装、更新、签名和发行指南，以及根目录文档和网站；纠正过时的当前版本／签名描述，撤下旧镜像下载指引。详见[文档检查记录](../audits/documentation-audit-2026-10-17.zh-CN.md)。
- 既有偏好、配对记录、Bonjour 服务、帧协议、Sparkle 密钥与 Android 签名证书保持不变。

## 升级与兼容

从 preview.2 或其他临时签名 Mac 版本首次升级时，可能需要重新授予屏幕录制、辅助功能和本地网络权限。改用固定身份后，后续构建保持代码身份连续；这不能覆盖用户拒绝、macOS 策略变化或未来主动迁移签名身份。

本次将新的 **build 18** 覆盖安装到 `/Applications/DisplayWeave.app` 中的本地固定签名 **17.1**：启动成功，屏幕录制和辅助功能仍为已允许，无需再授权。本地网络仍为原来的三个已开启条目，没有保留旧应用备份。此前固定签名 17 → 17.1 也已通过。网络开关状态不代替真实接收端流量验证，详见[权限延续](../../guides/mac-permissions.zh-CN.md)。

OpenDisplay 与 DisplayWeave 连接入口继续位于主界面。发送 Mac 选择“两种客户端”连接新旧接收端；接收端选择“OpenDisplay 兼容”接受旧发送端。旧版模式未加密且无需邀请；DisplayWeave 加密配对独立保留，详见[兼容覆盖](../../guides/opendisplay-compatibility.zh-CN.md)。按设备 Native/1080p/1440p/4K 扩展桌面分辨率保持可用，修改后重建该设备会话；镜像跟随源显示器，详见[桌面分辨率](../../guides/desktop-resolution.zh-CN.md)。

## 验证

- 签名源码 CI `38932980548` 的网站／文档、Android、Mac／Swift 均通过，包含 52 组 Swift、Android 测试／Lint、Mac universal Debug 和 iOS 模拟器构建。发行文档的 CI 在发行 PR 单独记录。
- 签名回归：20 项离线测试与既有 12 项 Apple 分发检查通过。真实双程序测试保留生产钥匙串传输身份与可信对端，随后只删除自己的测试命名空间。
- Build 18 打包：固定 Apple 签名 Mac universal Release、引导式 DMG／ZIP 一致性与嵌套签名、无签名 arm64 iOS Release、Android 测试与原 v2 证书 Release 均通过。
- 独立验证 ZIP Ed25519 签名、appcast 版本／大小／URL、Android 更新源／哈希／包名／证书，以及无签名 iOS 版本／身份；校验和覆盖其余全部发行文件。
- 本机覆盖安装验收见上。preview.2 的 TLS／Keystore／合成视频和更广泛 UI 观察保留为历史证据，没有作为本次签名发行的实机验收重新执行。

未确认独立在线显示器，因此跳过交互采集和虚拟显示测试。双设备 LAN／USB 性能、Intel 运行、所有历史 OpenDisplay 二进制、Pencil 硬件和耐久仍待验证。Apple Development 签名不等同于 Developer ID 公证，本版明确未公证；iOS 仍是需要用户有效身份的重签输入包。

## 下载

[GitHub Release](https://github.com/chenyuhao0628/displayweave/releases/tag/v0.3.0-preview.3)。八个文件包括四个平台包、两个更新源、`DisplayWeave-v0.3.0-preview.3-source.tar.gz` 和 `SHA256SUMS.txt`。源码包包含发行 tag 的跟踪源码、GPL-3.0、来源声明和构建脚本，哈希见校验和文件。二进制／源码仅使用 GitHub Releases，在线更新元数据使用 GitHub Pages，旧资产保持不变。

| 产物 | SHA-256 |
| --- | --- |
| `DisplayWeave-macOS.zip` | `b3a0a5e7d7dea6e9e487bd7e1f6b89e7bd3f3ddd597febbd99d7bf5276f41bd7` |
| `DisplayWeave-macOS.dmg` | `a29756e94f48f7eeab5968ed9c03e5aebaf0b74e743d69200748195dc6431518` |
| `DisplayWeave-Android.apk` | `370e1ba6b40cbeb9a66a3cfca280d0c5f9ab710d7b3d4a9468c4238c78646bf8` |
| `DisplayWeave-Preview-0.1-iOS-unsigned-resigning-input.ipa` | `83328fc764068b365b6726439c9a9f10dd22502a4244d74cbf7c78d5e862a29c` |
| `appcast.xml` | `42ceef4bb11625b042b4e1b08d92176ad2397f923d6a1b9f6dc9dc2584e15979` |
| `android-update.json` | `8f8dfb74f067240aa151908a0730b7bc822655d2b84d33ddff4ef4d3a61efd95` |

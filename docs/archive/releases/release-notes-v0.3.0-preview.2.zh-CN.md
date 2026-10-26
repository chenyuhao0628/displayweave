[English](release-notes-v0.3.0-preview.2.md) | [简体中文](release-notes-v0.3.0-preview.2.zh-CN.md)

> 历史记录：保留撰写时的版本、命令和结论，不作为当前操作指南。当前入口见[文档导航](../../README.zh-CN.md)。

# DisplayWeave v0.3.0-preview.2 — UI 与 OpenDisplay 兼容

版本 **0.3.0-preview.2**，Mac build / Android version code **17**，于 2026-10-16 从原生源码 `4f6e096` 本地构建。发行 tag 额外记录文档、网站/下载信息和准确更新源。本预览打包路径不要求正式 Apple 签名或公证。

## 改动

- UI 规范修订 2：中英文页面结构、组件令牌、状态、可访问性、文案与验收要求。
- Mac 发送/接收工作区、清晰的设置分组、完整错误文字、权限文字状态和菜单栏面板的“打开窗口”。
- iOS 等待/首次引导共用连接步骤，设备/状态卡片和配对优先设置；Android 引导面板、统一按钮与分组设置。
- Mac、iOS、Android 主界面直接提供 OpenDisplay 连接选择。发送端可在同一设备列表连接已配对 DisplayWeave 与旧 OpenDisplay。早期无安装 ID 的 hello 仅在显式匿名旧版连接计划中接受。
- 修正发送端把所有局域网描述成未加密的旧提示；已知身份、配对/撤销记录与 TLS 失败仍不能静默降级。
- 修复 Android 切换客户端模式时偶发的监听绑定冲突。初始重试总延迟最多 250 ms，停止时取消；持续端口占用仍提供恢复提示。

## 新旧客户端连接

DisplayWeave → OpenDisplay：发送 Mac 选择 **客户端兼容 → 兼容两种客户端**，再连接设备。OpenDisplay → DisplayWeave：接收端主界面选择 **OpenDisplay 兼容**，再从 OpenDisplay 连接。旧版模式无需邀请，未加密；DisplayWeave 加密连接继续使用邀请配对。接收端一次监听一种选定模式，切换会断开当前会话。

[兼容指南](../../guides/opendisplay-compatibility.zh-CN.md)列出已检查的协议代际和边界。核心连接兼容不代表所有上游可选功能或全部历史二进制均完成实体验收。

## 验证

本地通过：52 组 Swift、六组 Android Java、Mac Debug/Release 通用构建、iOS 模拟器与未签名 arm64 设备 Release、Android Debug/Release 与 Lint、真实 Apple↔Java TLS、Keychain/Keystore、隔离 iOS/Android 运行及主界面兼容模式恢复、网站/双语/发布检查、12 项打包测试、36 项品牌导出。匿名旧握手测试先失败再通过；已检查上游 `b9eec1f` hello/config 字段与真实合成 H.264 回环。

已检查 Mac 深色 UI 与 Command-comma、iOS 生产等待/首次引导/设置的深浅色和大字体、Android 等待/安全界面的深浅色及导航。[审核报告](../audits/ui-audit-2026-10-16.zh-CN.md)区分自动化、视觉与实体证据。未确认独立在线显示器，跳过虚拟显示/捕获交互。实际上游二进制/设备互通、USB/局域网性能、移动横屏、完整辅助技术、Mac 最小/浅色布局、Intel 运行、Pencil 硬件和耐久仍待验证。

打包检查验证 Mac DMG/ZIP 一致、通用架构、原 Sparkle 密钥与独立 Ed25519 验签、Android 原证书/版本和 iOS arm64 未签名边界。托管 CI 与在线发布检查单独记录在 GitHub Release。

Android 绑定冲突回归先失败再通过，包括持续占用与停止取消。一次性 AVD 中连续八次从主界面完成加密 → OpenDisplay → 加密切换，并通过退后台关闭监听检查。

## 下载

[GitHub Release](https://github.com/chenyuhao0628/displayweave/releases/tag/v0.3.0-preview.2)。八个文件包括四个平台包、两个更新源、`DisplayWeave-v0.3.0-preview.2-source.tar.gz` 和 `SHA256SUMS.txt`；校验文件覆盖其余七项。源码包含 GPL-3.0、上游署名与构建脚本。更新元数据使用项目 GitHub Pages，二进制/源码仅使用 GitHub Releases。

Mac 为 ad-hoc 签名、未公证，首次安装可能需系统允许。Android 保留原安装签名。iOS 是不能直接安装的未签名重签输入包。本任务的隔离开发/运行测试未覆盖替换已安装应用。

| 文件 | SHA-256 |
| --- | --- |
| `DisplayWeave-macOS.zip` | `ea46bc18891964c4be53d5875a74d88bb2555f04f6d9c59897572fe7153552b0` |
| `DisplayWeave-macOS.dmg` | `e98505756aa347b9c4bcb56f9bad1aa8c24ffac36719962e519f58e685ebb7d9` |
| `DisplayWeave-Android.apk` | `a3c4e1f2c98e55073d63b305aaca7e5bf31510be18069b9b7de3138a3ae332bb` |
| `DisplayWeave-Preview-0.1-iOS-unsigned-resigning-input.ipa` | `43010892e883272dc647e81943ed147368ad781631bdab8f345c488dd84f9d06` |
| `appcast.xml` | `4a22c5b49e73540943bd086273edd6601b5f4df292dfd6234214a794a2f92fd1` |
| `android-update.json` | `771d82a681f02ebe7edc9b8de1afb7955405d55633fde037e48eb10ea8c246f4` |

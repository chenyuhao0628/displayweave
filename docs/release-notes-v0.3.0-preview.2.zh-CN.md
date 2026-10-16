[English](release-notes-v0.3.0-preview.2.md) | [简体中文](release-notes-v0.3.0-preview.2.zh-CN.md)

# DisplayWeave v0.3.0-preview.2 — UI 与 OpenDisplay 兼容

版本 **0.3.0-preview.2**，Mac build / Android version code **17**，于 2026-10-16 从原生源码 `f8a2e67` 本地构建。发行 tag 额外记录文档、网站/下载信息和准确更新源。本预览打包路径不要求正式 Apple 签名或公证。

## 改动

- UI 规范修订 2：中英文页面结构、组件令牌、状态、可访问性、文案与验收要求。
- Mac 发送/接收工作区、清晰的设置分组、完整错误文字、权限文字状态和菜单栏面板的“打开窗口”。
- iOS 等待/首次引导共用连接步骤，设备/状态卡片和配对优先设置；Android 引导面板、统一按钮与分组设置。
- Mac、iOS、Android 主界面直接提供 OpenDisplay 连接选择。发送端可在同一设备列表连接已配对 DisplayWeave 与旧 OpenDisplay。早期无安装 ID 的 hello 仅在显式匿名旧版连接计划中接受。
- 修正发送端把所有局域网描述成未加密的旧提示；已知身份、配对/撤销记录与 TLS 失败仍不能静默降级。

## 新旧客户端连接

DisplayWeave → OpenDisplay：发送 Mac 选择 **客户端兼容 → 兼容两种客户端**，再连接设备。OpenDisplay → DisplayWeave：接收端主界面选择 **OpenDisplay 兼容**，再从 OpenDisplay 连接。旧版模式无需邀请，未加密；DisplayWeave 加密连接继续使用邀请配对。接收端一次监听一种选定模式，切换会断开当前会话。

[兼容指南](opendisplay-compatibility.zh-CN.md)列出已检查的协议代际和边界。核心连接兼容不代表所有上游可选功能或全部历史二进制均完成实体验收。

## 验证

本地通过：52 组 Swift、六组 Android Java、Mac Debug/Release 通用构建、iOS 模拟器与未签名 arm64 设备 Release、Android Debug/Release 与 Lint、真实 Apple↔Java TLS、Keychain/Keystore、隔离 iOS/Android 运行及主界面兼容模式恢复、网站/双语/发布检查、12 项打包测试、36 项品牌导出。匿名旧握手测试先失败再通过；已检查上游 `b9eec1f` hello/config 字段与真实合成 H.264 回环。

已检查 Mac 深色 UI 与 Command-comma、iOS 生产等待/首次引导/设置的深浅色和大字体、Android 等待/安全界面的深浅色及导航。[审核报告](ui-audit-2026-10-16.zh-CN.md)区分自动化、视觉与实体证据。未确认独立在线显示器，跳过虚拟显示/捕获交互。实际上游二进制/设备互通、USB/局域网性能、移动横屏、完整辅助技术、Mac 最小/浅色布局、Intel 运行、Pencil 硬件和耐久仍待验证。

打包检查验证 Mac DMG/ZIP 一致、通用架构、原 Sparkle 密钥与独立 Ed25519 验签、Android 原证书/版本和 iOS arm64 未签名边界。托管 CI 与在线发布检查单独记录在 GitHub Release。

## 下载

[GitHub Release](https://github.com/chenyuhao0628/displayweave/releases/tag/v0.3.0-preview.2)。八个文件包括四个平台包、两个更新源、`DisplayWeave-v0.3.0-preview.2-source.tar.gz` 和 `SHA256SUMS.txt`；校验文件覆盖其余七项。源码包含 GPL-3.0、上游署名与构建脚本。更新元数据使用项目 GitHub Pages，二进制/源码仅使用 GitHub Releases。

Mac 为 ad-hoc 签名、未公证，首次安装可能需系统允许。Android 保留原安装签名。iOS 是不能直接安装的未签名重签输入包。本任务的隔离开发/运行测试未覆盖替换已安装应用。

| 文件 | SHA-256 |
| --- | --- |
| `DisplayWeave-macOS.zip` | `8a1368123ed65cd4e4fea6912e62db5d40f6da7dc239bdf18b8312ff8216b8d1` |
| `DisplayWeave-macOS.dmg` | `2354ed9f43723b32c74999efffe11ba950f49699a45a8b17a8c64b71ad7f7305` |
| `DisplayWeave-Android.apk` | `cd00fd37422ff16c9d9b8860abb062dd98b0519dadb0c3fd3047532ecf41fab0` |
| `DisplayWeave-Preview-0.1-iOS-unsigned-resigning-input.ipa` | `50d0c7a7cadc49fc64bf79dc71afd3f6c755d59ac968307135e58f445d68a582` |
| `appcast.xml` | `af7c687f8a7c7646824345d6b0ff64ed04e16757a2898bad7e6cc99f9eba21ca` |
| `android-update.json` | `75bb67fdd2075770d2da72728099fe968ec7c4c53d590ef924b5c1f341dcc371` |

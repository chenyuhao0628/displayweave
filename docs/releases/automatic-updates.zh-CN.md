[English](automatic-updates.md) | [简体中文](automatic-updates.zh-CN.md)

# 自动更新认证与代码签名

DisplayWeave 把不可变的 Mac/Android 安装包发布到 GitHub Releases，把小型更新源发布到 GitHub Pages：

- Mac 更新源：`https://chenyuhao0628.github.io/displayweave/appcast.xml`
- Android 更新源：`https://chenyuhao0628.github.io/displayweave/android-update.json`
- Mac 首次安装产物：`DisplayWeave-macOS.dmg`（带引导的后续 Release）
- Mac 更新产物：`DisplayWeave-macOS.zip`
- Android 产物：`DisplayWeave-Android.apk`

当前正式发行版本是
[`v0.3.2`](https://github.com/chenyuhao0628/displayweave/releases)。
未支持当前更新路径的旧 Android 版本需要手动安装一次当前 APK；后续版本使用应用内的 GitHub 单源更新渠道。
本版本同时包含引导式 DMG 与 Sparkle ZIP 更新包。

v0.3.2 的 Mac 使用固定 Apple Development 身份，仍未公证。Sparkle 通过不变的内置 EdDSA 公钥验证 ZIP。更新真实性与权限延续分别验证：打包流程检查 Mac 签名身份，Sparkle 验证更新签名；这些都不等同于 Developer ID 公证发行。

2026-10-26：正式版构建 21 增加 iMac 4K/4.5K/5K 桌面档位与明确的逻辑尺寸标签，隔离可能阻塞的编码提交，并在不改变桌面布局的前提下适配持续编码压力。下载仅使用 GitHub Releases，Mac 与 Android 更新元数据使用项目 GitHub Pages。改动、权限延续与验证边界见[发布说明](v0.3.2.zh-CN.md)。

源码流程现已要求固定 Apple 签名身份和升级比较，见[权限延续](../guides/mac-permissions.zh-CN.md)，旧发行资产保持不可变；v0.3.2 与下载的构建 20 比较并延续其签名身份。本地发行的可复现命令与验收要求见[本地发行](local-release.zh-CN.md)。

## 用户一次性迁移

### Mac

1. Release 提供 `DisplayWeave-macOS.dmg` 时优先使用它：打开 DMG，把 DisplayWeave 拖入“应用程序”。从 ZIP 安装也完全等价，只要最终把 `DisplayWeave.app` 放入 `/Applications`；不要长期从 DMG、ZIP 或“下载”目录中运行。
2. 因为应用未公证，请按住 Control 点击应用并选择“打开”。如果仍被拦截，进入“系统设置 → 隐私与安全性 → 仍要打开”；仅在确认来自官方 Release 时继续。不需要全局开启“任何来源”。
3. 启动后检查屏幕录制、辅助功能和本地网络权限。临时签名升级及首次迁移到固定签名时可能需要重新授权；后续构建必须保持相同签名身份。

完成迁移后，Sparkle 会自动检查已签名 appcast 并可安装更高版本。Sparkle 位于 `DisplayWeave.app` 内部，而不属于 DMG 或 ZIP 容器，因此两种安装方式收到的后续更新完全相同；应用仍保留 Sparkle 的手动“检查更新”入口。EdDSA 签名不正确的版本会被拒绝。

### Android

1. 手动把首个支持更新的 APK 覆盖安装到现有 `app.opendisplay.android`。它必须继续使用现有 DisplayWeave 证书，否则 Android 会拒绝覆盖。
2. 应用回到前台时最多每 24 小时自动检查一次；“设置与帮助 → 检查更新”不受此限制。
3. 客户端只从严格匹配的 GitHub Release 路径下载。
4. 发现更新后，应用通过同一校验路径检查字节数、SHA-256、包名、版本号、最低 SDK 和签名证书；完整性或身份校验失败不会触发换源。
5. 首次更新时，Android 可能要求允许此应用“安装未知应用”。授权后返回 DisplayWeave。最终始终由 Android 系统安装器显示确认界面，不支持静默安装。

拒绝权限或安装不会影响接收端继续使用，也不会影响 Mac/iPhone 连接。

## 发布操作

当前正式版采用[本地发行](local-release.zh-CN.md)。流程使用固定 Mac 钥匙串身份、现有 Sparkle 钥匙串密钥和 Android keystore，不导出私钥。明确设置新版本／构建号，并通过 `DISPLAYWEAVE_MAC_BASELINE_APP` 与上一份已发布应用比较。只有首次从临时签名迁移到固定签名时使用 `DISPLAYWEAVE_ALLOW_ADHOC_MIGRATION=1`。

1. 构建 Mac DMG／ZIP、已签名 Android APK、无签名 iOS 重签输入包，并生成两个更新源。
2. 验证版本、哈希、归档内容、Mac 全部架构及签名连续性、Sparkle Ed25519 签名与 Android 固定证书。
3. 提交审查后的文档和 `public/` 中的原始更新源，合并前要求完整 CI。为验证过的提交打 tag，生成对应跟踪源码包。
4. 向 GitHub 草稿 Release 明确上传八个文件：四个平台包、两个更新源、源码包和校验和。公开前验证远端字节。
5. 先公开 Release，再合并发行 PR；main 的 Pages 部署随后发布网站与更新源。在线两个更新源应与 Release 附件逐字节一致。

托管 **Release** 工作流尚无维护者 Mac 身份和前一版本基线，会在预检处主动停止，也没有生成必需源码包的步骤。配置这些条件并补齐源码步骤之前，不把它作为完整发行路径。Sparkle／Android secret 名称保留在工作流中供后续配置，本次发行不上传新凭据。

禁止替换已发布资产或使用 `--clobber`。每次修正都使用更高构建号的新版本。

## 密钥备份与恢复

请对 Sparkle 私钥、Android JKS 及其 alias/密码分别保留两份加密离线备份。仓库中只允许出现 Sparkle 公钥和 Android 证书指纹。

- Sparkle 私钥丢失后，已安装的 Mac 无法信任新生成的更新密钥，只能再次手动迁移。
- Android JKS 或密码丢失后，新 APK 无法覆盖现有安装；只能卸载后重装，并可能丢失应用数据。
- 怀疑 secret 泄露时应立即停止发布、保留证据、轮换 GitHub secret，并按上述平台限制实施迁移。禁止把私钥提交到仓库。

## 更新源回滚与事故处理

Release 资产保持不可变。若要停止分发问题版本，把 `public/appcast.xml` 和 `public/android-update.json` 恢复到最近的已知正常版本并重新部署 Pages。更新源回滚只能阻止新下载，不能把已安装高版本的设备降级；这些设备必须通过更高 build number 的修复版本恢复。

公开更新源前运行：

```bash
DISPLAYWEAVE_VERSION_NAME=x.y.z DISPLAYWEAVE_BUILD_NUMBER=N \
  ./tools/verify-update-release.sh build/update-release
./tools/check-release-links.sh
./tools/check-bilingual-docs.sh
```

iOS 接收端不使用此更新渠道。它的 `_opensidecar._tcp`、端口 `9000`、长度前缀、H.264 兼容路径和旧 hello 默认值与 Mac/Android 发布保持独立。

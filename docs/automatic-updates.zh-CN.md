[English](automatic-updates.md) | [简体中文](automatic-updates.zh-CN.md)

# 无 Apple 开发者账号的自动更新

DisplayWeave 把不可变的 Mac/Android 安装包发布到 GitHub Releases，把小型更新源发布到 GitHub Pages：

- Mac 更新源：`https://chenyuhao0628.github.io/displayweave/appcast.xml`
- Android 更新源：`https://chenyuhao0628.github.io/displayweave/android-update.json`
- Mac 首次安装产物：`DisplayWeave-macOS.dmg`（带引导的后续 Release）
- Mac 更新产物：`DisplayWeave-macOS.zip`
- Android 产物：`DisplayWeave-Android.apk`

当前迁移版本是
[`v0.2.0-preview.3`](https://github.com/chenyuhao0628/displayweave/releases/tag/v0.2.0-preview.3)。
旧版本无法自行发现此更新渠道：请先手动安装本版本一次，后续版本再使用
自动更新。
本版本同时包含引导式 DMG 与 Sparkle ZIP 更新包。

Mac 版本采用 ad-hoc 签名且未公证。Sparkle 使用应用内置的 EdDSA 公钥验证 ZIP，因此后续更新不依赖 Apple Developer Program。它不会让首次下载自动获得 Gatekeeper 信任，也不等同于已公证正式发行。

## 用户一次性迁移

### Mac

1. Release 提供 `DisplayWeave-macOS.dmg` 时优先使用它：打开 DMG，把 DisplayWeave 拖入“应用程序”。从 ZIP 安装也完全等价，只要最终把 `DisplayWeave.app` 放入 `/Applications`；不要长期从 DMG、ZIP 或“下载”目录中运行。
2. 因为应用未公证，请按住 Control 点击应用并选择“打开”。如果仍被拦截，进入“系统设置 → 隐私与安全性 → 仍要打开”；仅在确认来自官方 Release 时继续。不需要全局开启“任何来源”。
3. 启动一次，并保留原有的屏幕录制、辅助功能和本地网络权限。以后移动或重命名应用，macOS 可能重新请求权限。

完成迁移后，Sparkle 会自动检查已签名 appcast 并可安装更高版本。Sparkle 位于 `DisplayWeave.app` 内部，而不属于 DMG 或 ZIP 容器，因此两种安装方式收到的后续更新完全相同；应用仍保留 Sparkle 的手动“检查更新”入口。EdDSA 签名不正确的版本会被拒绝。

### Android

1. 手动把首个支持更新的 APK 覆盖安装到现有 `app.opendisplay.android`。它必须继续使用现有 DisplayWeave 证书，否则 Android 会拒绝覆盖。
2. 应用回到前台时最多每 24 小时自动检查一次；“设置与帮助 → 检查更新”不受此限制。
3. 发现更新后，应用会校验字节数、SHA-256、包名、版本号、最低 SDK 和签名证书。
4. 首次更新时，Android 可能要求允许此应用“安装未知应用”。授权后返回 DisplayWeave。最终始终由 Android 系统安装器显示确认界面，不支持静默安装。

拒绝权限或安装不会影响接收端继续使用，也不会影响 Mac/iPhone 连接。

## 发布操作

GitHub Actions 必须配置且只需要以下 5 个仓库 secret：

- `SPARKLE_PRIVATE_KEY`
- `DISPLAYWEAVE_ANDROID_KEYSTORE_BASE64`
- `DISPLAYWEAVE_ANDROID_STORE_PASSWORD`
- `DISPLAYWEAVE_ANDROID_KEY_ALIAS`
- `DISPLAYWEAVE_ANDROID_KEY_PASSWORD`

手动运行 **Release** workflow。第一次运行可能只创建或更新 release-please PR；合并该 PR 后再次运行 **Release**。创建 Release 后，工作流以 tag 作为显示版本，以单调递增的 `github.run_number` 作为 Mac build number 和 Android version code，然后：

1. 构建并测试 ad-hoc Mac、无签名 iOS 兼容目标和已签名 Android；
2. 生成 EdDSA 签名的 appcast 与固定证书指纹的 Android JSON；
3. 校验版本、哈希、归档结构和 Android 签名；
4. 上传不可变资产；
5. 把两个签名更新源交给受保护的 Pages 部署 Job，不需要 Bot 向 `main` 提交。

已发布更新资产禁止替换，也禁止用 `--clobber` 覆盖。任何修正都必须发布更高 build number 的新版本。

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

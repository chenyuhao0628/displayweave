[English](development-preview.md) | [简体中文](development-preview.zh-CN.md)

# DisplayWeave `v0.3.0-preview.3` 开发分发

[GitHub Release](https://github.com/chenyuhao0628/displayweave/releases)

2026-10-17：构建 18 的 macOS 产物使用固定 Apple Development 签名。下载仅使用 GitHub Releases，Mac 与 Android 更新元数据使用项目 GitHub Pages。权限延续、保留的 OpenDisplay 兼容与构建证据见[发布说明](release-notes-v0.3.0-preview.3.zh-CN.md)。

| 平台/更新源 | 产物 | SHA-256 或信任边界 |
| --- | --- | --- |
| macOS 首次安装 | `DisplayWeave-macOS.dmg` | `a29756e94f48f7eeab5968ed9c03e5aebaf0b74e743d69200748195dc6431518`；固定 Apple Development 签名，未公证 |
| macOS 更新 | `DisplayWeave-macOS.zip` | `b3a0a5e7d7dea6e9e487bd7e1f6b89e7bd3f3ddd597febbd99d7bf5276f41bd7`；EdDSA 认证的 Sparkle 更新包 |
| Android | `DisplayWeave-Android.apk` | `370e1ba6b40cbeb9a66a3cfca280d0c5f9ab710d7b3d4a9468c4238c78646bf8`；项目固定密钥 v2 签名 |
| iOS/iPadOS | `DisplayWeave-Preview-0.1-iOS-unsigned-resigning-input.ipa` | `83328fc764068b365b6726439c9a9f10dd22502a4244d74cbf7c78d5e862a29c`；未签名自签输入包 |
| Mac 更新源 | `appcast.xml` | [配置的 Sparkle 更新源](https://chenyuhao0628.github.io/displayweave/appcast.xml) |
| Android 更新源 | `android-update.json` | [配置的元数据更新源](https://chenyuhao0628.github.io/displayweave/android-update.json) |
| 源码 | `DisplayWeave-v0.3.0-preview.3-source.tar.gz` | 发行 tag 的跟踪源码；哈希见校验和文件 |
| 校验和 | `SHA256SUMS.txt` | 覆盖以上七个 Release 文件 |

Android 签名证书 SHA-256：

```text
89805f045800ea18b56b84b32e8e31b1710a3c7bf3c85fda54d260d1fc6d589d
```

## 一次性迁移

- **Mac：** 手动替换 `/Applications` 中的旧应用。本版本没有 Developer
  ID 公证；请先核对来源和校验和，必要时按住 Control 点击并选择“打开”，
  或在“隐私与安全性”中选择“仍要打开”。后续版本可使用 EdDSA 认证的
  Sparkle 渠道。
- **Android：** p5 需要手动把此 APK 覆盖安装到现有包一次。p6 及以后
  下载统一来自对应的 GitHub Release。
  每个产物都会核对固定包身份和证书，但仍需要“安装未知应用”权限和系统
  最终确认。
- **iOS/iPadOS：** 输入包不能直接安装，用户必须提供有效签名身份；本版本
  不包含 iOS 自动更新。

可复现的版本化构建与发布见[本地发行](local-release.zh-CN.md)和[Mac 权限延续](mac-permissions.zh-CN.md)。Mac 身份、Sparkle 私钥和 Android keystore 保存在 Git 外，密码从 Keychain 读取而不打印。首次从临时签名 Mac 版本迁移可能需要再授权，后续构建比较前一发行版的代码身份要求。

Apple Development 签名用于本次未公证预览，不等同于 Developer ID 公证。无签名 iOS 输入包仍需要用户的有效签名身份，项目不背书第三方签名服务。

这仍是开发预览版，包含加密配对、Apple 刷新率目标协商和主界面 OpenDisplay 兼容入口。本构建的实体高刷新性能、双 Android 同时连接、受控 USB/WiFi 对比及 30 分钟/2 小时耐久仍未验证。

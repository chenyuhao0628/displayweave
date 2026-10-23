[English](development-preview.md) | [简体中文](development-preview.zh-CN.md)

# DisplayWeave `v0.3.0` 正式版分发

[GitHub Release](https://github.com/chenyuhao0628/displayweave/releases)

2026-10-23：正式版构建 19 加入 Mac 4K 延迟优化、100 Mbps H.264 局域网上限和逐项审查的上游恢复修复，沿用固定 Apple Development 签名。下载仅使用 GitHub Releases，Mac 与 Android 更新元数据使用项目 GitHub Pages。改动、权限延续与验证边界见[发布说明](release-notes-v0.3.0.zh-CN.md)。

| 平台/更新源 | 产物 | SHA-256 或信任边界 |
| --- | --- | --- |
| macOS 首次安装 | `DisplayWeave-macOS.dmg` | `ef709366b3535188274b3ef74c3f39c104132d7b1a61f00ff8881401543163cb`；固定 Apple Development 签名，未公证 |
| macOS 更新 | `DisplayWeave-macOS.zip` | `dacd185cbbce90361e5eb1e95ff7ebdd838f55c5d3ac704814d95e023e7ffaca`；EdDSA 认证的 Sparkle 更新包 |
| Android | `DisplayWeave-Android.apk` | `5db3982be3c8ef6b6fe8d3279b570d2173569c5a2041b5223527ccb3c536c763`；项目固定密钥 v2 签名 |
| iOS/iPadOS | `DisplayWeave-iOS-unsigned-resigning-input.ipa` | `9db070367ffe92ba4d77d5d8c574867dfce3e321e39b953ac5f3b5e9f1f86078`；未签名自签输入包 |
| Mac 更新源 | `appcast.xml` | [配置的 Sparkle 更新源](https://chenyuhao0628.github.io/displayweave/appcast.xml) |
| Android 更新源 | `android-update.json` | [配置的元数据更新源](https://chenyuhao0628.github.io/displayweave/android-update.json) |
| 源码 | `DisplayWeave-v0.3.0-source.tar.gz` | 发行 tag 的跟踪源码；哈希见校验和文件 |
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

Apple Development 签名用于本次未公证发行，不等同于 Developer ID 公证。无签名 iOS 输入包仍需要用户的有效签名身份，项目不背书第三方签名服务。

这是正式版，Mac 与 Mac 性能仍属实验性；包含加密配对、Apple 刷新率目标协商和主界面 OpenDisplay 兼容入口。本构建的实体高刷新性能、双 Android 同时连接、受控 USB/WiFi 对比及 30 分钟/2 小时耐久仍未验证。

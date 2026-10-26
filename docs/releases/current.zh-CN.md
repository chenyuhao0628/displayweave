[English](current.md) | [简体中文](current.zh-CN.md)

# DisplayWeave `v0.3.1` 正式版分发

[GitHub Release](https://github.com/chenyuhao0628/displayweave/releases)

2026-10-26：正式版构建 20 修复采集／编码恢复、拥塞后画质恢复和 Android 视频／触控比例，新增更清晰的分辨率／帧率设置，沿用固定 Apple Development 签名。下载仅使用 GitHub Releases，Mac 与 Android 更新元数据使用项目 GitHub Pages。改动、权限延续与验证边界见[发布说明](v0.3.1.zh-CN.md)。

| 平台/更新源 | 产物 | SHA-256 或信任边界 |
| --- | --- | --- |
| macOS 首次安装 | `DisplayWeave-macOS.dmg` | `50759c579713ee637cacf0106c4d8656dafaa8e4c1866bcb36f0a326c3b405c0`；固定 Apple Development 签名，未公证 |
| macOS 更新 | `DisplayWeave-macOS.zip` | `d567e1081f3bcf974a280935628083d99311c074a8a1ee80b0d9c1223663f8ca`；EdDSA 认证的 Sparkle 更新包 |
| Android | `DisplayWeave-Android.apk` | `3826c8ad64ae5924e78396a916f310adeb4bbef393f20799eca52b04de21716f`；项目固定密钥 v2 签名 |
| iOS/iPadOS | `DisplayWeave-iOS-unsigned-resigning-input.ipa` | `7a1dcae8d11449f7c64b08a1aa8b362bc6849d94353c9bc080ee30ad0803da3c`；未签名自签输入包 |
| Mac 更新源 | `appcast.xml` | [配置的 Sparkle 更新源](https://chenyuhao0628.github.io/displayweave/appcast.xml) |
| Android 更新源 | `android-update.json` | [配置的元数据更新源](https://chenyuhao0628.github.io/displayweave/android-update.json) |
| 源码 | `DisplayWeave-v0.3.1-source.tar.gz` | 发行 tag 的跟踪源码；哈希见校验和文件 |
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

可复现的版本化构建与发布见[本地发行](local-release.zh-CN.md)和[Mac 权限延续](../guides/mac-permissions.zh-CN.md)。Mac 身份、Sparkle 私钥和 Android keystore 保存在 Git 外，密码从 Keychain 读取而不打印。首次从临时签名 Mac 版本迁移可能需要再授权，后续构建比较前一发行版的代码身份要求。

Apple Development 签名用于本次未公证发行，不等同于 Developer ID 公证。无签名 iOS 输入包仍需要用户的有效签名身份，项目不背书第三方签名服务。

这是正式版，Mac 与 Mac 性能仍属实验性；包含加密配对、Apple 刷新率目标协商和主界面 OpenDisplay 兼容入口。本构建的实体高刷新性能、双 Android 同时连接、受控 USB/WiFi 对比及 30 分钟/2 小时耐久仍未验证。

本地已核验副本保存在 `artifacts/releases/v0.3.1/`。移除旧版本前，对照 GitHub 公开附件核验 7 文件清单。本表二进制哈希由 `pnpm run check:release` 与发布说明交叉检查。

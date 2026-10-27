[English](current.md) | [简体中文](current.zh-CN.md)

# DisplayWeave `v0.3.3` 正式版分发

[GitHub Release](https://github.com/chenyuhao0628/displayweave/releases)

2026-10-27：构建 22 根据可用的发送端和接收端显示器数据自动匹配 Mac 桌面。下载仅使用 GitHub Releases，Mac 与 Android 更新元数据使用项目 GitHub Pages。迁移、签名与验证边界见[发布说明](v0.3.3.zh-CN.md)。

| 平台/更新源 | 产物 | SHA-256 或信任边界 |
| --- | --- | --- |
| macOS 首次安装 | `DisplayWeave-macOS.dmg` | `f82afe0b140f461ef86338aa97092a83932261f15c7f87b3ca74af27eacb4499`；固定 Apple Development 签名，未公证 |
| macOS 更新 | `DisplayWeave-macOS.zip` | `32edbf42ea2641fae1c0e1f6ba0683cbe5367efc68c1c0d6301881e323fc3eb3`；EdDSA 认证的 Sparkle 更新包 |
| Android | `DisplayWeave-Android.apk` | `0945b4746f06ca0bce2720bb7ce048f6e61e2f76ffce5a147f574f174313f5fb`；项目固定密钥 v2 签名 |
| iOS/iPadOS | `DisplayWeave-iOS-unsigned-resigning-input.ipa` | `fd1eac2f82204154654245cbe887437da5086a845b92f21502fc98d0e0743a0e`；未签名自签输入包 |
| Mac 更新源 | `appcast.xml` | [配置的 Sparkle 更新源](https://chenyuhao0628.github.io/displayweave/appcast.xml) |
| Android 更新源 | `android-update.json` | [配置的元数据更新源](https://chenyuhao0628.github.io/displayweave/android-update.json) |
| 源码 | `DisplayWeave-v0.3.3-source.tar.gz` | 发行 tag 的跟踪源码；哈希见校验和文件 |
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

这是正式版，Mac 与 Mac 性能仍属实验性；桌面自动匹配是尺寸估算，不提供原生 5K 视频。本构建的客户双 Mac 匹配、实体高刷新性能、双 Android 同时连接、受控 USB/WiFi 对比及 30 分钟/2 小时耐久仍未验证。

本地已核验副本保存在 `artifacts/releases/v0.3.3/`。移除旧版本前，对照 GitHub 公开附件核验 7 文件清单。本表二进制哈希由 `pnpm run check:release` 与发布说明交叉检查。

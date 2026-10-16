[English](development-preview.md) | [简体中文](development-preview.zh-CN.md)

# DisplayWeave `v0.3.0-preview.2` 开发分发

[GitHub Release](https://github.com/chenyuhao0628/displayweave/releases)

2026-10-16：本预览版在本地构建，下载仅使用 GitHub Releases；Mac 与 Android 更新元数据使用已恢复访问的项目 GitHub Pages。UI 改造、OpenDisplay 兼容与构建证据见[发布说明](release-notes-v0.3.0-preview.2.zh-CN.md)。

| 平台/更新源 | 产物 | SHA-256 或信任边界 |
| --- | --- | --- |
| macOS 首次安装 | `DisplayWeave-macOS.dmg` | `e98505756aa347b9c4bcb56f9bad1aa8c24ffac36719962e519f58e685ebb7d9`；ad-hoc 签名且未公证 |
| macOS 更新 | `DisplayWeave-macOS.zip` | `ea46bc18891964c4be53d5875a74d88bb2555f04f6d9c59897572fe7153552b0`；EdDSA 认证的 Sparkle 更新包 |
| Android | `DisplayWeave-Android.apk` | `a3c4e1f2c98e55073d63b305aaca7e5bf31510be18069b9b7de3138a3ae332bb`；项目固定密钥 v2 签名 |
| iOS/iPadOS | `DisplayWeave-Preview-0.1-iOS-unsigned-resigning-input.ipa` | `43010892e883272dc647e81943ed147368ad781631bdab8f345c488dd84f9d06`；未签名自签输入包 |
| Mac 更新源 | `appcast.xml` | [配置的 Sparkle 更新源](https://chenyuhao0628.github.io/displayweave/appcast.xml) |
| Android 更新源 | `android-update.json` | [配置的元数据更新源](https://chenyuhao0628.github.io/displayweave/android-update.json) |
| 源码 | `DisplayWeave-v0.3.0-preview.2-source.tar.gz` | 发行 tag 的跟踪源码；哈希见校验和文件 |
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

先运行 `python3 -m pip install -r tools/dmg-requirements.txt` 安装固定版本的
DMG 元数据依赖，再运行 `./tools/package-preview-0.1.sh` 生成本地产物集合。Android keystore
位于 `~/Library/Application Support/DisplayWeave/Signing/`，密码存于
Keychain，均不得提交 Git。免费 Apple Personal Team 只适合维护者在已登记
设备测试，不适合公开通用分发；项目不背书第三方签名服务。

这仍是开发预览版，包含加密配对、Apple 刷新率目标协商和主界面 OpenDisplay 兼容入口。本构建的实体高刷新性能、双 Android 同时连接、受控 USB/WiFi 对比及 30 分钟/2 小时耐久仍未验证。

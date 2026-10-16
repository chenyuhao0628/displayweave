[English](development-preview.md) | [简体中文](development-preview.zh-CN.md)

# DisplayWeave `v0.2.1-p7` 开发分发

[GitHub Release](https://github.com/chenyuhao0628/displayweave/releases/tag/v0.2.1-p7)

| 平台/更新源 | 产物 | SHA-256 或信任边界 |
| --- | --- | --- |
| macOS 首次安装 | `DisplayWeave-macOS.dmg` | `26e9cf259410e731acfbe1a682444b71bf73d679298db6b00d82b3bef15ce0f6`；ad-hoc 签名且未公证 |
| macOS 更新 | `DisplayWeave-macOS.zip` | `dae40c3df8f9bbdebdce0484621a7d7a6a4c99c1b1a8504e9096fc8863705aef`；EdDSA 认证的 Sparkle 更新包 |
| Android | `DisplayWeave-Android.apk` | `ac1b5081259647c248e8c5d69aff4f477f4ebc9044a70c4a4602f6c81d6c2381`；项目固定密钥 v2 签名 |
| iOS/iPadOS | `DisplayWeave-Preview-0.1-iOS-unsigned-resigning-input.ipa` | `634305344f5cd7433a74a95166f781ea7313d5473ded88918528a3895e8eb1eb`；未签名自签输入包 |
| Mac 更新源 | `appcast.xml` | [在线 Sparkle 更新源](https://chenyuhao0628.github.io/displayweave/appcast.xml) |
| Android 更新源 | `android-update.json` | [在线已验证元数据](https://chenyuhao0628.github.io/displayweave/android-update.json) |
| 校验和 | `SHA256SUMS.txt` | 覆盖以上六个 Release 文件 |

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
  优先从 Cloudflare 下载，只把同一 GitHub Release 作为可用性备用源。
  每个产物都会核对固定包身份和证书，但仍需要“安装未知应用”权限和系统
  最终确认。
- **iOS/iPadOS：** 输入包不能直接安装，用户必须提供有效签名身份；本版本
  不包含 iOS 自动更新。

先运行 `python3 -m pip install -r tools/dmg-requirements.txt` 安装固定版本的
DMG 元数据依赖，再运行 `./tools/package-preview-0.1.sh` 生成本地产物集合。Android keystore
位于 `~/Library/Application Support/DisplayWeave/Signing/`，密码存于
Keychain，均不得提交 Git。免费 Apple Personal Team 只适合维护者在已登记
设备测试，不适合公开通用分发；项目不背书第三方签名服务。

这仍是开发预览版：不提供加密 WiFi 配对、iOS/iPadOS 120Hz，也尚未完成
双 Android、同条件 USB/WiFi 受控 Benchmark 及 30 分钟/2 小时耐久证据。

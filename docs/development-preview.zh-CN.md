[English](development-preview.md) | [简体中文](development-preview.zh-CN.md)

# DisplayWeave `v0.2.1-p4` 开发分发

[GitHub Release](https://github.com/chenyuhao0628/displayweave/releases/tag/v0.2.1-p4)

| 平台/更新源 | 产物 | SHA-256 或信任边界 |
| --- | --- | --- |
| macOS 首次安装 | `DisplayWeave-macOS.dmg` | `a41539f180a2d1854307d70cfaa7328ec14348bdee7ce242e9e478df0f265c50`；ad-hoc 签名且未公证 |
| macOS 更新 | `DisplayWeave-macOS.zip` | `28cc452cce5168db3813834f59fbb0ad290ac7a30cba83c5f79337bb5cf36a8a`；EdDSA 认证的 Sparkle 更新包 |
| Android | `DisplayWeave-Android.apk` | `11f3b7ce1e765aced8d1dfd255edfda83641f36db0863f37c6a948305e5c7820`；项目固定密钥 v2 签名 |
| iOS/iPadOS | `DisplayWeave-Preview-0.1-iOS-unsigned-resigning-input.ipa` | `a43b7b99c861f9d4f60c85f0ce0bcc57e21c428fb106317df89a42fe8966d15a`；未签名自签输入包 |
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
- **Android：** 把此 APK 覆盖安装到现有包。后续应用内下载会核对固定
  包身份和证书，但仍需要“安装未知应用”权限和系统最终确认；DisplayWeave
  不能静默安装 APK。
- **iOS/iPadOS：** 输入包不能直接安装，用户必须提供有效签名身份；本版本
  不包含 iOS 自动更新。

先运行 `python3 -m pip install -r tools/dmg-requirements.txt` 安装固定版本的
DMG 元数据依赖，再运行 `./tools/package-preview-0.1.sh` 生成本地产物集合。Android keystore
位于 `~/Library/Application Support/DisplayWeave/Signing/`，密码存于
Keychain，均不得提交 Git。免费 Apple Personal Team 只适合维护者在已登记
设备测试，不适合公开通用分发；项目不背书第三方签名服务。

这仍是开发预览版：不提供加密 WiFi 配对、iOS/iPadOS 120Hz，也尚未完成
双 Android、同条件 USB/WiFi 受控 Benchmark 及 30 分钟/2 小时耐久证据。

[English](development-preview.md) | [简体中文](development-preview.zh-CN.md)

# DisplayWeave `v0.2.1-p8` 开发分发

[GitHub Release](https://github.com/chenyuhao0628/displayweave/releases/tag/v0.2.1-p8)

2026-10-16：GitHub Actions 暂不可用，本版改为本地构建。GitHub 公开访问和 Pages 更新源仍返回 404；请使用 [Cloudflare 下载页](https://downloads.urlget.cyou/displayweave/zh.html)。Mac／Android 应用内检查更新仍依赖原 Pages 地址，在恢复前请手动覆盖安装。镜像中的更新源副本不会自动修改客户端地址。

| 平台/更新源 | 产物 | SHA-256 或信任边界 |
| --- | --- | --- |
| macOS 首次安装 | `DisplayWeave-macOS.dmg` | `f3c043d53cce3b459ce36f62ea640e70dfce9a3c9165cf2ec0326ee9d6b4579a`；ad-hoc 签名且未公证 |
| macOS 更新 | `DisplayWeave-macOS.zip` | `a83e6a0a0455bfe7f0c0a5b5cb70f4a1acdbc18b1f8f00c3e76f9eea419ac67c`；EdDSA 认证的 Sparkle 更新包 |
| Android | `DisplayWeave-Android.apk` | `3f909af1bd0e6da09a72048b124d061aadd8284c2dad7beb0b8a3e7f568a098e`；项目固定密钥 v2 签名 |
| iOS/iPadOS | `DisplayWeave-Preview-0.1-iOS-unsigned-resigning-input.ipa` | `8e423d4c6baf60d3b92c990f1d465473c223bce539baf3456abf59799f079bd1`；未签名自签输入包 |
| Mac 更新源 | `appcast.xml` | [配置的 Sparkle 更新源](https://chenyuhao0628.github.io/displayweave/appcast.xml) |
| Android 更新源 | `android-update.json` | [配置的元数据更新源](https://chenyuhao0628.github.io/displayweave/android-update.json) |
| 源码 | `DisplayWeave-v0.2.1-p8-source.tar.gz` | 发行 tag 的跟踪源码；哈希见校验和文件 |
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

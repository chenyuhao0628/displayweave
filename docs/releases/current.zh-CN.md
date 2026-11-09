[English](current.md) | [简体中文](current.zh-CN.md)

# DisplayWeave `v0.3.4` 正式版分发

[GitHub Release](https://github.com/chenyuhao0628/displayweave/releases/tag/v0.3.4)

2026-11-09：构建 23 包含 Android 实验性高帧率与后台保活、iPad 原生分辨率高刷试验、代码加固和 Mac 圆角图标。请求或协商的 FPS 不等于实体屏幕实测刷新率。详见[发行说明](v0.3.4.zh-CN.md)。

| 平台/更新源 | 产物 | SHA-256 或信任边界 |
| --- | --- | --- |
| macOS 首次安装 | `DisplayWeave-macOS.dmg` | `afb5f775f2dcee8765a5f1bb490659b6b85d9f4d10112fc5f1f2d8e44538a6c6`；固定 Apple Development 签名，未公证 |
| macOS 更新 | `DisplayWeave-macOS.zip` | `0b5d6e4c97bf77e2c0354b258e36950711e5a2ef35b1279c8bb191426c5c4db6`；EdDSA 认证的 Sparkle 更新包 |
| Android | `DisplayWeave-Android.apk` | `30d06443d73c0b39157fb17e4a8ec97d2d56009fda2ad184a5a8c03e19230d4b`；项目固定密钥 v2 签名 |
| iOS/iPadOS | `DisplayWeave-iOS-unsigned-resigning-input.ipa` | `a23e19b9d34d340396439fa6833d8ec842c78f9c40121f088e66c18ba0ed12e9`；无签名 arm64 自签输入包 |
| Mac 更新源 | `appcast.xml` | [配置的 Sparkle 更新源](https://chenyuhao0628.github.io/displayweave/appcast.xml) |
| Android 更新源 | `android-update.json` | [配置的元数据更新源](https://chenyuhao0628.github.io/displayweave/android-update.json) |
| 源码 | `DisplayWeave-v0.3.4-source.tar.gz` | 发行 tag 的跟踪源码；哈希见校验和文件 |
| 校验和 | `SHA256SUMS.txt` | 覆盖以上七个 Release 文件 |

Android 签名证书 SHA-256：

```text
89805f045800ea18b56b84b32e8e31b1710a3c7bf3c85fda54d260d1fc6d589d
```

## 安装边界

- **Mac：** 使用引导式 DMG，或从 ZIP 安装应用。应用沿用 Apple Development 签名身份，但没有 Developer ID 公证；若 macOS 阻止启动，请按官方首次运行提示操作。后续 ZIP 更新由 Sparkle 验证。
- **Android：** 覆盖安装到原有包。Android 可能要求用户允许安装未知应用，并显示系统最终确认。
- **iOS/iPadOS：** IPA 无签名，不能直接安装；需要有效 Apple 签名身份。

Android 高帧率试验和 iPad 原生分辨率高刷选项均为实验功能。持续实体刷新率、双设备串流、Intel 运行和耐久仍属于独立实机验收项目。Mac 签名连续性以下载的 v0.3.3 应用为基线。详见[本地发行](local-release.zh-CN.md)和[Mac 权限延续](../guides/mac-permissions.zh-CN.md)。

本地已核验副本：`artifacts/releases/v0.3.4/`。`pnpm run check:release` 会将当前二进制哈希与发行说明交叉检查。

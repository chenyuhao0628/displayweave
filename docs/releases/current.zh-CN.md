[English](current.md) | [简体中文](current.zh-CN.md)

# DisplayWeave `v0.3.5` 正式版分发

[GitHub Release](https://github.com/chenyuhao0628/displayweave/releases/tag/v0.3.5)

2026-11-10：构建 24 加固 Android 旧版 V1 解码恢复与异步编解码器释放、iOS Metal 绘制尺寸／代次同步及旋转视频准入、Mac 接收端解码后窗口呈现门禁、ADB/usbmux 管道与握手超时边界，并完整同步双语文档。请求或协商的 FPS 不等于实体屏幕实测刷新率。详见[发行说明](v0.3.5.zh-CN.md)。

| 平台/更新源 | 产物 | SHA-256 或信任边界 |
| --- | --- | --- |
| macOS 首次安装 | `DisplayWeave-macOS.dmg` | `ddcbe28b170d2efa9f160ad1d376986cbf137f0a5af7bcba9352266db2a7ec70`；固定 Apple Development 签名，未公证 |
| macOS 更新 | `DisplayWeave-macOS.zip` | `eb88bf026dba990b0f1d3bc89dfcd7963884be79f6409b33206d43b8675aa6bc`；EdDSA 认证的 Sparkle 更新包 |
| Android | `DisplayWeave-Android.apk` | `25387fafb821321797a3d6a4ef79101ce89225b613edb63c9e65f642912e1db6`；项目固定密钥 v2 签名 |
| iOS/iPadOS | `DisplayWeave-iOS-unsigned-resigning-input.ipa` | `b79c1bbbe23c8a07b57df9be52d808ac68aee9471edd716251c81681253560b1`；无签名 arm64 自签输入包 |
| Mac 更新源 | `appcast.xml` | [配置的 Sparkle 更新源](https://chenyuhao0628.github.io/displayweave/appcast.xml) |
| Android 更新源 | `android-update.json` | [配置的元数据更新源](https://chenyuhao0628.github.io/displayweave/android-update.json) |
| 源码 | `DisplayWeave-v0.3.5-source.tar.gz` | 发行 tag 的跟踪源码；哈希见校验和文件 |
| 校验和 | `SHA256SUMS.txt` | 覆盖以上七个 Release 文件 |

Android 签名证书 SHA-256：

```text
89805f045800ea18b56b84b32e8e31b1710a3c7bf3c85fda54d260d1fc6d589d
```

## 安装边界

- **Mac：** 使用引导式 DMG，或从 ZIP 安装应用。应用沿用 Apple Development 签名身份，但没有 Developer ID 公证；若 macOS 阻止启动，请按官方首次运行提示操作。后续 ZIP 更新由 Sparkle 验证。
- **Android：** 覆盖安装到原有包。Android 可能要求用户允许安装未知应用，并显示系统最终确认。
- **iOS/iPadOS：** IPA 无签名，不能直接安装；需要有效 Apple 签名身份。

Android 高帧率试验和 iPad 原生分辨率高刷选项均为实验功能。持续实体刷新率、双设备串流、Intel 运行和耐久仍属于独立实机验收项目。Mac 签名连续性以 v0.3.4 应用为基线。详见[本地发行](local-release.zh-CN.md)和[Mac 权限延续](../guides/mac-permissions.zh-CN.md)。

本地已核验副本：`artifacts/releases/v0.3.5/`。`pnpm run check:release` 会将当前二进制哈希与发行说明交叉检查。

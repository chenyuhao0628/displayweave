[English](release-notes-v0.2.0-preview.2.md) | [简体中文](release-notes-v0.2.0-preview.2.zh-CN.md)

# DisplayWeave `v0.2.0-preview.2` 发布说明

[GitHub prerelease](https://github.com/chenyuhao0628/displayweave/releases/tag/v0.2.0-preview.2)

## Mac 热修复

- Release 版本现在会忽略仅供 Benchmark 使用的 `testPattern` 偏好，即使
  旧偏好域曾把启用值迁移过来。
- 偏好迁移不再复制调试专用色板键。
- 旋转/重建会在移除虚拟显示器前关闭旧色板；断开会取消待创建任务并关闭
  窗口，防止 macOS 把失去目标显示器的全屏色板迁移到主屏。

这修复了 iPhone 上持续变色的画面，以及 Mac 主屏残留色板、必须退出应用
才消失的问题。iOS/OpenDisplay 的发现、分帧、H.264、hello 与输入协议均未改变。

## 应用内更新

已经运行 `v0.2.0-preview.1`（build 2）的 Mac 可以使用 Sparkle 应用内
“检查更新”安装本 build 3。appcast 中的归档继续由应用内置的同一 EdDSA
公钥认证；Mac 分发仍为 ad-hoc 签名且未公证。

Android 也从 version code 2 升到 3，可以使用应用内检查更新；包名和固定
签名证书不变。iOS 产物仍是未签名自签输入包，不使用自动更新。

## 产物

| 文件 | SHA-256 |
| --- | --- |
| `DisplayWeave-macOS.zip` | `0c0bbd61625a90ef5264097da3f25db0d77c1383421e506a97aab0c6eb50b501` |
| `DisplayWeave-Android.apk` | `04a7433deb4fa893ef95f216d9b4e35e01ff5466bda56d801b88792b0122b2e1` |
| `DisplayWeave-Preview-0.1-iOS-unsigned-resigning-input.ipa` | `7a188576fec361daff62efbbb978f9800ae4fac55d269ffbfecb1806646289f4` |
| `appcast.xml` | `523252198c6bbd987281a9a60225576a53ba18e1f6421fbb2604be837868ec1f` |
| `android-update.json` | `25764708231ddcbc3f8eb7796a7ce8a9108ca10a9bee06665ccba2c49da09bd1` |

Android 签名证书 SHA-256 保持为
`89805f045800ea18b56b84b32e8e31b1710a3c7bf3c85fda54d260d1fc6d589d`。

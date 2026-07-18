[English](release-notes-v0.2.1-p6.md) | [简体中文](release-notes-v0.2.1-p6.zh-CN.md)

# DisplayWeave `v0.2.1-p6` 发布说明

DisplayWeave 0.2.1-p6 为无法连接 GitHub Release 下载服务的网络增加 Android
双源更新渠道。

## Android 更新分发

- 默认从 Cloudflare Pages 上的 `downloads.urlget.cyou` 下载 APK。
- 只有发生连接失败、HTTP 服务不可用或传输中断时，才切换到相同 GitHub
  Release 中的备用 APK。
- 两个地址都必须使用 HTTPS，并严格匹配受信任的主机名和发布路径。
- 无论来自哪个下载源，最终都经过同一套大小、SHA-256、包名、版本、SDK
  和固定签名证书校验。
- 如果出现文件超出声明大小、最终大小不符、哈希失败、包名不符、版本不符
  或证书失败，会立即终止，不通过换源绕过安全检查。

Android p5 尚不信任新的 Cloudflare 域名，需要从网站手动覆盖安装一次 p6；
p6 及以后版本即可自动使用 Cloudflare，并在其网络不可用时回退到 GitHub。

## 分发内容

本版本继续提供带引导的 macOS DMG、Sparkle ZIP、已签名 Android APK、未签名
iOS 自签输入包、已签名更新源和 `SHA256SUMS.txt`。

| 产物 | SHA-256 |
| --- | --- |
| `DisplayWeave-macOS.zip` | `d1b5bef839322f34d0cd31067aa78776108a6014233677869fb394b3bc12b44a` |
| `DisplayWeave-macOS.dmg` | `441651dcb54304f2ec147ebdc35db7808d92812631496b99e17f41394f31c691` |
| `DisplayWeave-Android.apk` | `123fea1468335f8412b0f8620623c3c9fa681b36ef5e9e3190e3b1ec2c812083` |
| `DisplayWeave-Preview-0.1-iOS-unsigned-resigning-input.ipa` | `7430569bb68db065a056f827b0538eca780a65455dbed3ce0d69e3503c0320a8` |
| `appcast.xml` | `bf1429a9774c2a2661136832902bc4e032a32b0b83108ea3b567ff206dd7df0c` |
| `android-update.json` | `4fc43c7606b40f786d21872ab3dd1243ecd79308237e75cb3aaff1e84acdb377` |

[GitHub Release](https://github.com/chenyuhao0628/displayweave/releases/tag/v0.2.1-p6) · [Cloudflare 镜像](https://downloads.urlget.cyou/releases/v0.2.1-p6/SHA256SUMS.txt)

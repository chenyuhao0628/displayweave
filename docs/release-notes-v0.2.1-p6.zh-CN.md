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

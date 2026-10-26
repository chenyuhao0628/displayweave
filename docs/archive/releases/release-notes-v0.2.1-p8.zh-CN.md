[English](release-notes-v0.2.1-p8.md) | [简体中文](release-notes-v0.2.1-p8.zh-CN.md)

> 历史记录：保留撰写时的版本、命令和结论，不作为当前操作指南。当前入口见[文档导航](../../README.zh-CN.md)。

# DisplayWeave `v0.2.1-p8` 发布说明

版本 `0.2.1-p8`，Mac build／Android version code `15`，2026-10-16 本地构建发行。本版沿用 p7 已审查的原生功能源码；因托管 Actions 不可用而改用本地构建，并保留 p7 文件与 tag 不变。

## 内容

包含 p7 的 Mac 双角色单向扩展／镜像、硬件 HEVC 与 H.264 回退、绑定接口的直连候选发现、协商后的 Pencil 压感／倾角／悬停、四端 UI 及会话生命周期加固。详见 [p7 说明](release-notes-v0.2.1-p7.zh-CN.md)和[使用指南](../../guides/hevc-wired-pencil.zh-CN.md)。p8 没有新增原生功能或分辨率模式选择器，未改变签名密钥、应用 ID、更新源地址及通信协议。

新增可复现的[本地发行流程](../../releases/local-release.zh-CN.md)，保留历史产物并提供对应源码包。源码来自发行 tag 的跟踪文件，包含 GPL-3.0、上游声明与构建脚本。

发行后续提交还修复了中文路由 hydration 切回英文的问题。应用安装包仍是不可变的 p8 tag 产物。

## 自动验证与真机边界

本地执行 37 组 Swift 自测、Mac arm64/x86_64 Debug 和 Release、iOS Simulator Debug 和无签名 arm64 Release、六组 Android 自测及 Debug/已签名 Release、生产网站构建、双语文档和发行链接检查。构建环境为 Xcode 26.6（17F113）、OpenJDK 21.0.10、pnpm 10.33.0。

`verify-update-release.sh` 验证包内版本、DMG/ZIP 一致性、深度代码签名、Android 固定证书与哈希；另以 CryptoKit 验证 Sparkle ZIP Ed25519，检查 Mac 双架构、iOS 无签名身份与版本。托管 Actions 不可用，本版不宣称托管 CI 通过。

双 Mac 真机路由／性能、真实 Pencil 压感／倾角／悬停／防误触、新 UIKit 手势运行、Intel 运行及 30 分钟／2 小时耐久仍待验收。本机无已验证的独立在线显示器，虚拟显示交互跳过；自动检查不代表屏幕实测性能。

## 下载与更新

[发行页面](https://github.com/chenyuhao0628/displayweave/releases) · [GitHub Release](https://github.com/chenyuhao0628/displayweave/releases)

八项文件为 Mac DMG／Sparkle ZIP、Android APK、无签名 iOS 自签输入包、`appcast.xml`、`android-update.json`、`DisplayWeave-v0.2.1-p8-source.tar.gz` 及 `SHA256SUMS.txt`。源码包的 SHA-256 见校验和清单，该清单覆盖其余七项文件。

Mac 保持 ad-hoc 签名且未公证；Android 保留原包名与固定证书，可覆盖安装；iOS IPA 需个人有效签名后安装。2026-10-16，已认证 GitHub 管理接口可用，但公开 GitHub／Pages 返回 404。这是历史可用性观察，不是当前下载指引。外部镜像已停用，请使用[分发指南](../../releases/current.zh-CN.md)链接的当前 GitHub Release 与 GitHub Pages 更新源。

## 产物完整性

| 产物 | SHA-256 |
| --- | --- |
| `DisplayWeave-macOS.zip` | `a83e6a0a0455bfe7f0c0a5b5cb70f4a1acdbc18b1f8f00c3e76f9eea419ac67c` |
| `DisplayWeave-macOS.dmg` | `f3c043d53cce3b459ce36f62ea640e70dfce9a3c9165cf2ec0326ee9d6b4579a` |
| `DisplayWeave-Android.apk` | `3f909af1bd0e6da09a72048b124d061aadd8284c2dad7beb0b8a3e7f568a098e` |
| `DisplayWeave-Preview-0.1-iOS-unsigned-resigning-input.ipa` | `8e423d4c6baf60d3b92c990f1d465473c223bce539baf3456abf59799f079bd1` |
| `appcast.xml` | `a16c4277d46e6f30185c629a060f356f341bb76dc5adb268cc1907ed4a662d47` |
| `android-update.json` | `b032f7cc19c963b5559306c3459e402fb5b87466f6e48d9b98044e68ea012ba2` |

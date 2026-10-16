[English](release-notes-v0.3.0-preview.1.md) | [简体中文](release-notes-v0.3.0-preview.1.zh-CN.md)

# DisplayWeave `v0.3.0-preview.1` 发布说明

版本 `0.3.0-preview.1`，Mac 构建号／Android version code 为 **16**，于 2026-10-16 本地构建。原生构建源码为 `53d2dfa`；发行 tag 仅追加文档、网站文案与原始更新源，不改变原生代码或打包输入。对应 tag 源码包保留 GPL-3.0、上游声明和构建脚本。

## 变更

- 按接收设备保存原生/1080p/1440p/4K 扩展桌面分辨率；镜像保持实体源显示器几何。
- Apple 与 Android 默认采用固定证书指纹的双向 TLS，支持两分钟邀请配对、持久信任、撤销和显式未加密旧版兼容。
- Apple 硬件 HEVC、H.264 回退及有界 30–120fps 目标；请求 FPS 不等于实测性能。
- 双端同意的 Mac 接收键鼠回传及可选的同安装身份有线/Wi-Fi 切换，工作有界且会话资源按归属清理。
- 认证连接上的 Pencil 旋转/橡皮及可配置双击/挤压动作；发送端定义的快捷键映射需要独立许可。
- 进程 CPU 指标、Android 有界帧缓冲租借、共用协议样例、Android 自适应图标及 Apple 正式打包预检工具。
- 修复 iOS 视图归属：旧视图迟到的销毁不能清除新视图回调或移除其视频层。

## 升级与配对

**请同时升级发送端和接收端。** 在接收端“安全与配对”生成邀请，导入发送 Mac。局域网、ADB USB 和 Apple USB 使用相同认证流。参见[配对](secure-transport.zh-CN.md)、[分辨率](desktop-resolution.zh-CN.md)、[Mac 输入](mac-receiver-input.zh-CN.md)及[高级 Pencil](pencil-advanced.zh-CN.md)。

连接旧版时，需在新版的对应角色中显式开启不安全旧版兼容，并使用可信网络。认证失败不会回退明文；有配对历史的设备不能静默降级。已存设置、应用标识、Sparkle 密钥及 APK 签名证书保持兼容。本版为预览，不代表实机验收完成。

## 验证

本地门禁通过：**52 组 Swift**、六组 Android Java 测试、Android Debug/Release 与 Lint、Mac 双架构 Debug/Release、iOS 模拟器与无签名 arm64 设备构建、网站构建、双语文档和发行检查。执行了真实 Apple↔Java TLS、Mac/iOS Keychain 和 Android Keystore。隔离 iOS runtime 覆盖加密视频/Pencil、视图替换、撤销与退后台关闭；隔离 Android 覆盖配对/TLS/UI 和自适应图标解析。12 项 Apple 离线打包测试与 36 项品牌导出检查通过。

安装包验证覆盖 DMG/ZIP 一致性、Mac 深度签名、双架构、原 Sparkle Ed25519 签名、原 APK 证书/版本/哈希及 iOS 无签名边界。发行前已将本机 Mac 应用替换为 build 16，包内和本机保存的更新源均指向项目 GitHub Pages appcast；旧安装备份保留在本地、不进入 Git。

双 Mac 实际路由/输入、ProMotion/HEVC 吞吐、Pencil 硬件/绘图软件、Intel 运行、分配/延迟对比和 30 分钟/2 小时耐久仍待完成。未确认独立在线显示器，因此跳过桌面采集和虚拟显示交互。模拟器/合成检查不能证明实机性能。Apple 正式分发身份及批准的最终可编辑品牌母版仍是外部前提。

## 分发与完整性

从 [GitHub Release](https://github.com/chenyuhao0628/displayweave/releases/tag/v0.3.0-preview.1) 下载。八项文件均在 GitHub：四个平台包、两个更新源、`DisplayWeave-v0.3.0-preview.1-source.tar.gz` 和 `SHA256SUMS.txt`。校验和覆盖其余七项，包含对应源码包。Mac/Android 元数据使用仓库 GitHub Pages，不使用其他下载主机或备用源。

Mac 为 ad-hoc 签名、未公证，首次安装可能需 macOS 确认；Android 保留原签名身份，可覆盖安装；iOS 是未签名重签输入包，需有效个人签名身份。旧 p6/p7 草稿和 p8 构建记录不能证明下载已公开。

| 产物 | SHA-256 |
| --- | --- |
| `DisplayWeave-macOS.zip` | `c4cb42af68f0479d8fc884ae3c631655a24dca5ce5000ed9d2b3e81214e88cc7` |
| `DisplayWeave-macOS.dmg` | `820bad434a200cba3e7ef2d7acad0b3f052fcef6c479d57a1d8efb5bb1d5ac29` |
| `DisplayWeave-Android.apk` | `72e158c825f8ba16ac14677312167ee83a72aa6590b089c788dc54521c1b3057` |
| `DisplayWeave-Preview-0.1-iOS-unsigned-resigning-input.ipa` | `ba881f0c23e3a992ce0ca615ee245b8c638765b06e65dac0a9b3f913d51db965` |
| `appcast.xml` | `159a629e28cfb739479c86471ad521d967414e7835764a1e536e623cdcb73ce6` |
| `android-update.json` | `0a41d1c4635bf94803e946e3bad133172a7de319831daf9e0ab0c6ec8c3ee452` |

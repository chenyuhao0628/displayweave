[English](release-notes-v0.3.0.md) | [简体中文](release-notes-v0.3.0.zh-CN.md)

> 历史记录：保留撰写时的版本、命令和结论，不作为当前操作指南。当前入口见[文档导航](../../README.zh-CN.md)。

# DisplayWeave v0.3.0

发布日期：2026-10-23。**正式版**，Mac build / Android version code 为 **19**。原生源码基线：`929eb93`。本版本包含 Mac 4K 延迟优化，以及逐项审查适配的上游采集/显示器恢复修复。上一版为 v0.3.0-preview.3（18）。

## 改动

- 60 FPS 时允许两帧异步编码在途，与既有 90/120 FPS 策略一致。接收端背压允许短暂阻塞，必要时等待关键帧恢复；所有工作仍有明确上限。
- 发送端每 8 ms 独立采样光标，只保留最新待发位置，优先发送尚未提交的光标控制；接收端合并投递，减少可避免的光标延迟，分帧格式不变。
- H.264 局域网上限从 60 提高到 **100 Mbps**，开放手动 80/100 Mbps；以太网和 Wi-Fi 共用该策略。Auto 在边界内适配，持续无拥塞且有视频活动后恢复初始目标；4K60、H.264、清晰模式仍从约 49.77 Mbps 起步。100 Mbps 是目标，不代表实测吞吐或保证画面更流畅。
- 低延迟模式不受支持时，以关闭该模式的方式重试编码器创建，保留编码协商和硬件要求。创建/准备失败会传递到会话清理并提供可重试错误。Mac 接收端 15 秒内未收到可用首帧样本会超时，避免一直显示已连接却没有视频。
- 采集丢帧后补发最新画面；恢复睡眠/锁屏后的采集，并检测持续的错误采集区域。重试有界，按设备保留显示排列，有序恢复属于本应用的虚拟显示器冲突；旧会话不能修改替换后的会话。
- 记录实际网络接口、编码器模式、采集/编码/发送速率、光标投递和接收端背压，合并重复错误。诊断统计不包含桌面像素、按键或光标坐标。
- 正式发行资产使用中性名称，包括 `DisplayWeave-iOS-unsigned-resigning-input.ipa`；同步更新双语下载和升级指南。

本机证据见 [4K 审计](../../verification/mac-4k-latency.zh-CN.md)。[上游集成记录](../audits/upstream-integration-2026-10-23.zh-CN.md)逐项列出来源提交、适配和测试，包含晚于上游 v1.26.0 的三个 Mac 修复。保留 GPL-3.0 和上游署名。

## 升级与兼容

两台 Mac 都安装本版本。扩展桌面选择 4K；镜像模式跟随源显示器。需要请求 100 Mbps 时，选择 H.264 和**手动 → 100 Mbps**。默认仍为 Auto。此前明确关闭的低延迟偏好不会自动打开；启用后遇到不支持的请求时，由新回退机制处理。

Mac 沿用构建 18 的固定 Apple Development 身份。打包时已与下载的构建 18 应用比较代码身份要求、团队、bundle ID 和通用架构，确认连续性。本次没有覆盖安装现有应用，因此未交互重测 18 → 19 的隐私权限保留；之前的固定签名覆盖证据见 [Mac 权限](../../guides/mac-permissions.zh-CN.md)。首次从临时签名版本迁移仍可能需要再次授权。

**本正式版尚未使用 Developer ID 签名或公证。** 首次安装请验证校验和，将应用放入 `/Applications`；若被 macOS 阻止，按指南在**隐私与安全性 → 仍要打开**中恢复。Android 保留固定签名证书；iOS 包仍未签名，用户需用自己的有效签名身份重签后才能安装。

保留 bundle/package ID、偏好、配对记录、Bonjour 服务、分帧、Sparkle 密钥、Android 签名及 USB/切换策略。主界面的 OpenDisplay 显式兼容连接和 DisplayWeave 认证配对继续可用。Mac 和 Android 使用[现有的验证更新渠道](../../releases/automatic-updates.zh-CN.md)。

## 自动验证

- 60 组独立 Swift 套件；arm64 和 x86_64 通用 Mac Debug 编译；iOS 模拟器 Debug 编译。
- 固定签名通用 Mac Release、引导式 DMG/ZIP 内容及嵌套签名检查；无签名 arm64 iOS Release；Android 测试、Debug/Lint 和已签名 Release APK。
- 真实 Apple↔Java TLS、Mac/iOS 钥匙串持久化和恢复、隔离 iOS 的 TLS/视频/生命周期/Pencil 检查，以及 Android Keystore/TLS/撤销/旧模式运行检查。
- 两个独立签名测试程序在隔离命名空间内保留钥匙串身份和配对；20 项签名回归、12 项分发检查及 36 项品牌资产检查通过。
- 使用内置公钥独立验证 ZIP 的 Ed25519 签名；核对更新源 URL、版本、构建号、长度、哈希、iOS 归档内容与固定 Android 证书。
- 网站生产构建、96 对双语文档、发布链接和空白检查。发行提交上的托管 CI 在发布 PR 中单独记录，与本地结果区分。

完整日志保存在被忽略的 `build/release-v0.3.0-audit/` 和 `build/diagnostics/upstream-review-2026-10-23/`。此前在本机 arm64 上运行的 3840×2160 H.264 合成探针，在两种请求码率下均以约 60 FPS 编码 180/180 帧；没有经过实体接收端，也没有证明实际达到 100 Mbps 流量。

## 实机验证与待办

**SKIP：**Intel/macOS 15 运行、双 iMac 以太网显示/延迟、实际睡眠唤醒、多显示器恢复及持续 4K60。接收窗口和虚拟显示器夹具仅编译、未运行；未确认交互测试所需的独立显示会话。没有重启 WindowServer 或远程访问服务。

双设备 LAN/USB 对照、Pencil 硬件、双 Android 并发和 30 分钟/2 小时耐久仍待完成。编译、回环流量和合成策略测试不能证明这些硬件结果。最初反馈的黑屏与屏幕录制权限相关，未证实 H.264 本身是原因。

## 下载

[GitHub Release](https://github.com/chenyuhao0628/displayweave/releases/tag/v0.3.0)。共八个资产：四个平台包、两个更新源、`DisplayWeave-v0.3.0-source.tar.gz` 和 `SHA256SUMS.txt`。源码包包含发行 tag 的完整跟踪源码、GPL-3.0、署名与构建脚本，其哈希在校验和文件中。二进制和源码仅通过 GitHub Releases 分发；在线更新源使用 GitHub Pages。旧资产保持不可变。

| 资产 | SHA-256 |
| --- | --- |
| `DisplayWeave-macOS.zip` | `dacd185cbbce90361e5eb1e95ff7ebdd838f55c5d3ac704814d95e023e7ffaca` |
| `DisplayWeave-macOS.dmg` | `ef709366b3535188274b3ef74c3f39c104132d7b1a61f00ff8881401543163cb` |
| `DisplayWeave-Android.apk` | `5db3982be3c8ef6b6fe8d3279b570d2173569c5a2041b5223527ccb3c536c763` |
| `DisplayWeave-iOS-unsigned-resigning-input.ipa` | `9db070367ffe92ba4d77d5d8c574867dfce3e321e39b953ac5f3b5e9f1f86078` |
| `appcast.xml` | `9c620b488e08c0968ec19a60ff4829d98ec4aae082b56c1f764573eef1b98dc4` |
| `android-update.json` | `6315667d6aadabecf7c18f6ecc039b9f74b96f7105568152cc4e59f485e89669` |

Android 签名证书 SHA-256：`89805f045800ea18b56b84b32e8e31b1710a3c7bf3c85fda54d260d1fc6d589d`。

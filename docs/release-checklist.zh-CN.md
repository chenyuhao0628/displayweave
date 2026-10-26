[English](release-checklist.md) | [简体中文](release-checklist.zh-CN.md)

# 发布检查清单

## 当前正式版：v0.3.1（20）

[发布说明](release-notes-v0.3.1.zh-CN.md)记录可靠性、视频恢复、Android 几何／输入和设置改进。原生源码为 `c0f8f8a`（PR #19，审查版本 `cd57957`）。后续直接正式发布，不经过公开候选版或预览版阶段。

- [x] 审查源码 CI `40217422986` 通过：61 组 Swift 及恢复／准入夹具、通用 Mac Debug、iOS 模拟器、七组 Android Java／Debug／Lint 和网站／文档。
- [x] 源码验收记录真实 TLS／钥匙串及隔离 iOS／Android 安全、生命周期、视频／输入与体验检查，实机结果单独记录。
- [x] 构建 20 的 Mac Release／DMG／ZIP 与下载的实际构建 19 保持签名身份一致；嵌套签名、加固运行时、Mac 双架构、原 Android 证书及无签名 arm64 设备 IPA 验证通过。
- [x] 独立 Sparkle Ed25519 签名及产物／更新源版本、身份、URL、大小与哈希检查通过。

发行／合并前要求发行提交完整 CI、八个远端文件验证、GitHub 正式版状态、merge commit 保留 tag 祖先关系，以及 Pages 在线更新源字节完全匹配。最终在线结果记录在发布 PR 和 Release。本次未交互复测构建 19 → 20 隐私权限延续。Mac 仍采用 Apple Development 签名且未公证；iOS 需要重签。实机采集／旋转／睡眠恢复、Intel、双设备性能、高刷、无障碍与耐久仍待完成。

## 历史 v0.3.0（19）

[发布说明](release-notes-v0.3.0.zh-CN.md)记录 Mac 4K 延迟、100 Mbps H.264 局域网上限、逐项审查的上游恢复、产物哈希和实机边界。原生源码为 `929eb93`。

- [x] 60 组 Swift、通用 Mac Debug、iOS 模拟器 Debug 和 Android 测试/Debug/Lint 通过。
- [x] 真实 Apple↔Java TLS、隔离 Mac/iOS 钥匙串、iOS TLS/视频/Pencil/生命周期及 Android Keystore/TLS/撤销检查通过。
- [x] 20 项签名回归、12 项分发检查、36 项品牌资产及真实双程序钥匙串/签名延续通过。
- [x] 构建 19 的 Mac Release/DMG/ZIP 已与下载的实际构建 18 比较签名身份；无签名 arm64 iOS 与原证书 Android Release 验证通过。
- [x] 独立验证 Sparkle Ed25519 签名、更新源/产物身份、版本、大小和哈希。

发行要求：发行提交完整 CI 通过、八个远端文件验证、GitHub 正式版（非 prerelease）、merge commit 保留 tag 祖先关系，以及 Pages 在线更新源字节完全匹配。托管与在线结果单独记录在发布 PR 和 Release。本次未执行 18 → 19 交互式权限升级测试。

实机 Intel/macOS 15、双 iMac 以太网 4K60、实际睡眠唤醒、多显示器恢复与耐久仍待验证。正式版沿用 Apple Development 签名且未公证；iOS 需要重签。

## 历史 v0.3.0-preview.3（18）

[发布说明](release-notes-v0.3.0-preview.3.zh-CN.md)记录固定 Mac 签名、哈希和验证边界。原生／签名基线 `92b5834` 保留 preview.2 的 UI、协议和应用标识。[文档检查](documentation-audit-2026-10-17.zh-CN.md)覆盖当前指南与历史引用清理。

- [x] 签名源码 CI `38932980548` 三项任务通过，包含 52 组 Swift、Android 测试／Lint 和 Apple 兼容构建。
- [x] 20 项签名回归、12 项分发检查、真实双程序钥匙串延续、本机固定签名 17 → 17.1 权限延续通过。
- [x] Build 18 Mac universal Release 和 DMG／ZIP 签名／内容、Android 原证书 Release、无签名 arm64 iOS 输入包验证通过。
- [x] 独立验证 Sparkle Ed25519 签名及全部更新源／产物身份、版本、大小和哈希。
- [x] 将实际 build 18 覆盖安装到固定签名 17.1；屏幕录制／辅助功能仍已允许，本地网络三个条目仍开启，未保留旧应用备份。

发行门禁：核对八个远端文件（四个平台包、两个更新源、源码、校验和），公开 Release，再在发行提交的完整 CI 通过后合并。原样持久化更新源，Pages 部署后比较在线字节。托管检查与在线验收记录在发行 PR 和 GitHub Release；本地通过本身不证明在线可用。

实机缺口仍包括双设备 LAN／USB 性能、Intel／Pencil 和耐久。没有独立在线显示器时跳过采集／虚拟显示交互。本预览采用 Apple Development，未做 Developer ID 公证；iOS 仍需重签。

## 历史 v0.2.1-p2 证据

以下条目只记录 p2，不能证明 p8 或未来版本已验证。

## 已发布身份

- Release：https://github.com/chenyuhao0628/displayweave/releases/tag/v0.2.1-p2
- 版本：`v0.2.1-p2`
- 单调递增 Mac build / Android version code：`9`
- Release Tag 目标提交：`cddaaad248a89ec3a4b387fb8a38cb090681895e`
- 成功的发布前 CI run：`29384709884`
- 成功的 Release run：`29384932159`
- 成功的 Build job：`87256105382`
- 成功的 Pages/更新源 job：`87256476833`

## 产物与完整性

| 产物 | SHA-256 / 检查 |
| --- | --- |
| `DisplayWeave-macOS.zip` | `2a009eb1cdade8ac532a826a78d00f75cbb2d526c41742e6d849bfc4691294b7` |
| `DisplayWeave-macOS.dmg` | `09d09270e332e705a0b9088f84b7e709a4b560dce56f157c04278fd6a6bde633` |
| `DisplayWeave-Android.apk` | `28efb42c0f8459ee5aabf4702369ae6cacfd691c0251fef25e2b9d1101376390` |
| `DisplayWeave-Preview-0.1-iOS-unsigned-resigning-input.ipa` | `4580df6a947aa94da3ab9f237e72a9ff60211ce15a7a1660f1a4177325d19f99` |
| `appcast.xml` | `6f2f1f322c7bdbe7db8ba0d9b442594251cde23b6ba116e2a7405e1b650aaa3f` |
| `android-update.json` | `0ac96cbcf9991248dc79338c1a85f86120ba645aa4fee858d06ad3ff76f8ee12` |
| `SHA256SUMS.txt` | 已存在并覆盖以上六个文件 |

Android 签名证书 SHA-256：

```text
89805f045800ea18b56b84b32e8e31b1710a3c7bf3c85fda54d260d1fc6d589d
```

- [x] GitHub 显示七个不可变资产全部上传。
- [x] Mac 应用为 universal ad-hoc 签名，并明确未公证。
- [x] Android APK 使用一个 Signer、固定证书和 v2 签名。
- [x] iOS IPA 是未签名 arm64 自签输入包，不能直接安装。

## 构建与自动验证

- [x] 手动触发工作流，输入为 `release_tag=v0.2.1-p2` 与 `build_number=9`。
- [x] Workflow Head 与 Release Tag Target 均为 `cddaaad248a89ec3a4b387fb8a38cb090681895e`。
- [x] Mac Release 与未签名 iOS 兼容构建完成。
- [x] Android 签名 Release Build 与六组 Android Self Test 全部成功。
- [x] `apksigner` 报告 v2 签名、一个 Signer 与固定证书。
- [x] Archive 结构、显示版本、更新 URL、大小、哈希、Package Identity 与签名通过 `verify-update-release.sh`。
- [x] 该目标提交此前还通过 22 个 Swift Standalone Test、Android 61-task Debug Build、无签名 macOS/iOS Debug Build，以及 Production Site/文档检查。

## 更新渠道检查

- [x] 在线 Mac Feed：https://chenyuhao0628.github.io/displayweave/appcast.xml
- [x] 在线 Android Feed：https://chenyuhao0628.github.io/displayweave/android-update.json
- [x] Android 在线 Feed 与 Release 资产逐字节一致。仓库持久化的 Sparkle XML 只相差末尾换行；Version、Build、URL、Length 与 EdDSA Enclosure Signature 均与 Release 资产一致。
- [x] Mac Feed 声明 Short Version `0.2.1-p2`、build `9`、ZIP 大小 `2739582` 与 Release EdDSA 签名。
- [x] Android Feed 声明 Version Code `9`、APK 大小 `222164`、预期包名、SHA-256、Minimum SDK 与固定证书。
- [x] 仓库 `public/` Feed 包含相同值，后续 Pages 部署不会把更新渠道回退到 Preview 5。
- [x] Release run `29384932159` 已覆盖并成功部署签名 Feed；仓库 Feed 持久化为 `0.2.1-p2 (9)`，防止后续部署回退。

## 兼容与披露

- [x] 未协商 Android-only Capability 时，Legacy OpenDisplay iOS 继续使用 Length-prefix + JSON Telemetry + Annex-B H.264。
- [x] 首次安装说明披露 Gatekeeper/ad-hoc 签名、Android 未知来源确认与未签名 iOS 边界。
- [x] 发布说明区分代码/构建证据与待补真机证据，不做无数据的延迟结论。
- [x] 中英文 Release 链接使用 GitHub 绝对路径；简体中文源文件发布于 `docs/release-notes-v0.2.1-p2.zh-CN.md`。

## 待补真机证据

- [ ] 在已连接硬件上执行完整 Android 快速恢复 V2 矩阵。
- [ ] 完成同条件 USB/WiFi 受控矩阵。
- [ ] 复测 Legacy OpenDisplay iOS/TestFlight Runtime。
- [ ] 完成双 Android 真机测试。
- [ ] 完成计划中的 30 分钟与 2 小时耐久测试。
- [ ] 在已连接接收端上重复断开/重连计时与旧 Connection Callback 压力测试。

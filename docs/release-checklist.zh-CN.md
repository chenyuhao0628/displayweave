[English](release-checklist.md) | [简体中文](release-checklist.zh-CN.md)

# 发布检查清单

## 当前发行：v0.3.0-preview.2（17）

[发布说明](release-notes-v0.3.0-preview.2.zh-CN.md)记录UI 与兼容改动、哈希和签名边界。原生源码 `4f6e096` 已通过完整本地回归；Mac universal、Android 原证书签名 APK 与无签名 iOS 重签输入包已完成 Release 构建。本机已安装应用保持不变，开发检查使用隔离 app。

52 组 Swift、六组 Android、真实平台 TLS/Keychain/Keystore、iOS/Android 隔离运行、Apple 构建、Android Lint、网站、双语、12 项打包测试及 36 项品牌导出检查通过。DMG/ZIP 一致性、原 Sparkle 签名、Android 证书/版本及 iOS 无签名边界均已核验。

八项文件包括四个平台包、两个更新源、对应 tag 源码及校验和。公开前核验远端文件，原样持久化 feed 并在部署后比对在线字节。仅使用 GitHub Releases 与 GitHub Pages；不覆盖已发布产物。托管 CI 与本地结果分别记录，不因本地通过而代称远端成功。

双 Mac/Pencil/Intel 与耐久仍待实机验收；没有独立在线显示器时跳过虚拟显示交互。正式 Apple 身份与最终可编辑品牌素材仍待外部条件。

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

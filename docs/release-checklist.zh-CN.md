[English](release-checklist.md) | [简体中文](release-checklist.zh-CN.md)

# `v0.2.0-preview.4` 发布检查清单

## 已发布身份

- Release：https://github.com/chenyuhao0628/displayweave/releases/tag/v0.2.0-preview.4
- 版本：`v0.2.0-preview.4`
- 单调递增 Mac build / Android version code：`5`
- Release 目标提交：`f300f88e84423f2a895d8b15dc3e514362e050bc`
- 成功的 Release run：`29347755688`
- 成功的 Build job：`87135822940`
- 成功的 Pages/更新源 job：`87136937478`

## 产物与完整性

| 产物 | SHA-256 / 检查 |
| --- | --- |
| `DisplayWeave-macOS.zip` | `28cc452cce5168db3813834f59fbb0ad290ac7a30cba83c5f79337bb5cf36a8a` |
| `DisplayWeave-macOS.dmg` | `a41539f180a2d1854307d70cfaa7328ec14348bdee7ce242e9e478df0f265c50` |
| `DisplayWeave-Android.apk` | `11f3b7ce1e765aced8d1dfd255edfda83641f36db0863f37c6a948305e5c7820` |
| `DisplayWeave-Preview-0.1-iOS-unsigned-resigning-input.ipa` | `a43b7b99c861f9d4f60c85f0ce0bcc57e21c428fb106317df89a42fe8966d15a` |
| `appcast.xml` | `4eedf2ce46dc4908de8b8a414f8dd860d8a09042c2cdc9c206dc360428d37049` |
| `android-update.json` | `c225d438f89c615d167a3448016626205a20bb6d12190c58b48742283b33dceb` |
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

- [x] 手动触发工作流，输入为 `release_tag=v0.2.0-preview.4` 与 `build_number=5`。
- [x] Workflow Head 与 Release Target 均为 `f300f88e84423f2a895d8b15dc3e514362e050bc`。
- [x] Mac Release 与未签名 iOS 兼容构建完成。
- [x] Android 签名 Release Build 完成：72 个 Actionable Task 与六组 Android Self Test 全部通过。
- [x] `apksigner` 报告 v2 签名、一个 Signer 与固定证书。
- [x] Archive 结构、显示版本、更新 URL、大小、哈希、Package Identity 与签名通过 `verify-update-release.sh`。
- [x] 该目标提交此前还通过 22 个 Swift Standalone Test、Android 61-task Debug Build、无签名 macOS/iOS Debug Build，以及 Production Site/文档检查。

## 更新渠道检查

- [x] 在线 Mac Feed：https://chenyuhao0628.github.io/displayweave/appcast.xml
- [x] 在线 Android Feed：https://chenyuhao0628.github.io/displayweave/android-update.json
- [x] Android 在线 Feed 与 Release 资产逐字节一致。仓库持久化的 Sparkle XML 只相差末尾换行；Version、Build、URL、Length 与 EdDSA Enclosure Signature 均与 Release 资产一致。
- [x] Mac Feed 声明 Short Version `0.2.0-preview.4`、build `5`、ZIP 大小 `2714987` 与新的 EdDSA 签名。
- [x] Android Feed 声明 Version Code `5`、APK 大小 `213308`、预期包名、SHA-256、Minimum SDK 与固定证书。
- [x] 仓库 `public/` Feed 包含相同值，后续 Pages 部署不会把更新渠道回退到 preview.3。

## 兼容与披露

- [x] 未协商 Android-only Capability 时，Legacy OpenDisplay iOS 继续使用 Length-prefix + JSON Telemetry + Annex-B H.264。
- [x] 首次安装说明披露 Gatekeeper/ad-hoc 签名、Android 未知来源确认与未签名 iOS 边界。
- [x] 发布说明区分代码/构建证据与待补真机证据，不做无数据的延迟结论。

## 待补真机证据

- [ ] 在已连接硬件上执行完整 Android 快速恢复 V2 矩阵。
- [ ] 完成同条件 USB/WiFi 受控矩阵。
- [ ] 复测 Legacy OpenDisplay iOS/TestFlight Runtime。
- [ ] 完成双 Android 真机测试。
- [ ] 完成计划中的 30 分钟与 2 小时耐久测试。

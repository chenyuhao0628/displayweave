[English](release-checklist.md) | [简体中文](release-checklist.zh-CN.md)

# `v0.2.1-p1` 发布检查清单

## 已发布身份

- Release：https://github.com/chenyuhao0628/displayweave/releases/tag/v0.2.1-p1
- 版本：`v0.2.1-p1`
- 单调递增 Mac build / Android version code：`8`
- Release Tag 目标提交：`2fb57b4b341c85104a4f1a6e8cf0ecd08dd6754f`
- 成功的发布前 CI run：`29383103136`
- 成功的 Release run：`29383334404`
- 成功的 Build job：`87251419579`
- 成功的 Pages/更新源 job：`87251982032`

## 产物与完整性

| 产物 | SHA-256 / 检查 |
| --- | --- |
| `DisplayWeave-macOS.zip` | `702e1857335eb3349d301cfd9085718c03e9f6cdb933dfd16bf7b382dfa1dd91` |
| `DisplayWeave-macOS.dmg` | `993b7e7e8969cf377eb6500fa9681f51a2761ca493bd77c1ff5ada94ebc51b5c` |
| `DisplayWeave-Android.apk` | `0c77365c49647813a0a9a2aeff217cab550432b028d66c3b19398ba043f65140` |
| `DisplayWeave-Preview-0.1-iOS-unsigned-resigning-input.ipa` | `4502da624205b526334c05452389d2b2ba9130582bd7a136b6831db8d029b964` |
| `appcast.xml` | `1ec636ab38f9cc8ac6e72e6aee795316ad33f679916f507e363d84f1da4e3412` |
| `android-update.json` | `cf9269e9971bcae3890799ef062b4ae89fe40adeff0231daf9972012374ac005` |
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

- [x] 手动触发工作流，输入为 `release_tag=v0.2.1-p1` 与 `build_number=8`。
- [x] Workflow Head 与 Release Tag Target 均为 `2fb57b4b341c85104a4f1a6e8cf0ecd08dd6754f`。
- [x] Mac Release 与未签名 iOS 兼容构建完成。
- [x] Android 签名 Release Build 与六组 Android Self Test 全部成功。
- [x] `apksigner` 报告 v2 签名、一个 Signer 与固定证书。
- [x] Archive 结构、显示版本、更新 URL、大小、哈希、Package Identity 与签名通过 `verify-update-release.sh`。
- [x] 该目标提交此前还通过 22 个 Swift Standalone Test、Android 61-task Debug Build、无签名 macOS/iOS Debug Build，以及 Production Site/文档检查。

## 更新渠道检查

- [x] 在线 Mac Feed：https://chenyuhao0628.github.io/displayweave/appcast.xml
- [x] 在线 Android Feed：https://chenyuhao0628.github.io/displayweave/android-update.json
- [x] Android 在线 Feed 与 Release 资产逐字节一致。仓库持久化的 Sparkle XML 只相差末尾换行；Version、Build、URL、Length 与 EdDSA Enclosure Signature 均与 Release 资产一致。
- [x] Mac Feed 声明 Short Version `0.2.1-p1`、build `8`、ZIP 大小 `2739581` 与 Release EdDSA 签名。
- [x] Android Feed 声明 Version Code `8`、APK 大小 `219380`、预期包名、SHA-256、Minimum SDK 与固定证书。
- [x] 仓库 `public/` Feed 包含相同值，后续 Pages 部署不会把更新渠道回退到 Preview 5。
- [x] Release run `29383334404` 已覆盖并成功部署签名 Feed；仓库 Feed 持久化为 `0.2.1-p1 (8)`，防止后续部署回退。

## 兼容与披露

- [x] 未协商 Android-only Capability 时，Legacy OpenDisplay iOS 继续使用 Length-prefix + JSON Telemetry + Annex-B H.264。
- [x] 首次安装说明披露 Gatekeeper/ad-hoc 签名、Android 未知来源确认与未签名 iOS 边界。
- [x] 发布说明区分代码/构建证据与待补真机证据，不做无数据的延迟结论。
- [x] 中英文 Release 链接使用 GitHub 绝对路径；简体中文源文件发布于 `docs/release-notes-v0.2.1-p1.zh-CN.md`。

## 待补真机证据

- [ ] 在已连接硬件上执行完整 Android 快速恢复 V2 矩阵。
- [ ] 完成同条件 USB/WiFi 受控矩阵。
- [ ] 复测 Legacy OpenDisplay iOS/TestFlight Runtime。
- [ ] 完成双 Android 真机测试。
- [ ] 完成计划中的 30 分钟与 2 小时耐久测试。
- [ ] 在已连接接收端上重复断开/重连计时与旧 Connection Callback 压力测试。

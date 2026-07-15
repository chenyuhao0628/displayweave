[English](release-checklist.md) | [简体中文](release-checklist.zh-CN.md)

# `v0.2.1` 发布检查清单

## 已发布身份

- Release：https://github.com/chenyuhao0628/displayweave/releases/tag/v0.2.1
- 版本：`v0.2.1`
- 单调递增 Mac build / Android version code：`7`
- Release Tag 目标提交：`80c923fb24e9c23399128262bf65727886d1c5a0`
- 成功的 Release run：`29355318964`
- 成功的 Build job：`87161369291`
- 成功的 Pages/更新源 job：`87162225134`
- 成功的发布后 CI run：`29356107557`

## 产物与完整性

| 产物 | SHA-256 / 检查 |
| --- | --- |
| `DisplayWeave-macOS.zip` | `ee507c6d3b4ddd80c7bdf3142ffe268cc06d5539950cd9298207c30de3a836fe` |
| `DisplayWeave-macOS.dmg` | `fc2964c6f5a7088269b5b6637db2df2d0fc3dc95abd134d427a998b8fa976fc1` |
| `DisplayWeave-Android.apk` | `3b0d0e3be13ea195867573746cf1938bc835f654391770b7269c3fbdfbbb494a` |
| `DisplayWeave-Preview-0.1-iOS-unsigned-resigning-input.ipa` | `50dd56b234c54d1e57aa64e7941eb2fe88e70640a128da284decb25cb850114e` |
| `appcast.xml` | `04111c2406e9efab99756604eb8bcc91abbb7a89de51117e26291f4c9a0c0cd9` |
| `android-update.json` | `b8383d74f91a066fa68734990a7250b4bc6c23d13e487035cb452c70de0f572c` |
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

- [x] 手动触发工作流，输入为 `release_tag=v0.2.1` 与 `build_number=7`。
- [x] Workflow Head 与 Release Tag Target 均为 `80c923fb24e9c23399128262bf65727886d1c5a0`。
- [x] Mac Release 与未签名 iOS 兼容构建完成。
- [x] Android 签名 Release Build 与六组 Android Self Test 全部成功。
- [x] `apksigner` 报告 v2 签名、一个 Signer 与固定证书。
- [x] Archive 结构、显示版本、更新 URL、大小、哈希、Package Identity 与签名通过 `verify-update-release.sh`。
- [x] 该目标提交此前还通过 22 个 Swift Standalone Test、Android 61-task Debug Build、无签名 macOS/iOS Debug Build，以及 Production Site/文档检查。

## 更新渠道检查

- [x] 在线 Mac Feed：https://chenyuhao0628.github.io/displayweave/appcast.xml
- [x] 在线 Android Feed：https://chenyuhao0628.github.io/displayweave/android-update.json
- [x] Android 在线 Feed 与 Release 资产逐字节一致。仓库持久化的 Sparkle XML 只相差末尾换行；Version、Build、URL、Length 与 EdDSA Enclosure Signature 均与 Release 资产一致。
- [x] Mac Feed 声明 Short Version `0.2.1`、build `7`、ZIP 大小 `2723141` 与 Release EdDSA 签名。
- [x] Android Feed 声明 Version Code `7`、APK 大小 `216324`、预期包名、SHA-256、Minimum SDK 与固定证书。
- [x] 仓库 `public/` Feed 包含相同值，后续 Pages 部署不会把更新渠道回退到 Preview 5。
- [x] 发布后的 Pages 部署曾暴露仓库中旧的 Preview 5 Feed；持久化提交 `0259c1a` 已修正，并重新确认在线 Feed 为 `0.2.1 (7)`。

## 兼容与披露

- [x] 未协商 Android-only Capability 时，Legacy OpenDisplay iOS 继续使用 Length-prefix + JSON Telemetry + Annex-B H.264。
- [x] 首次安装说明披露 Gatekeeper/ad-hoc 签名、Android 未知来源确认与未签名 iOS 边界。
- [x] 发布说明区分代码/构建证据与待补真机证据，不做无数据的延迟结论。
- [x] 中英文 Release 链接使用 GitHub 绝对路径，简体中文页面返回 HTTP 200。

## 待补真机证据

- [ ] 在已连接硬件上执行完整 Android 快速恢复 V2 矩阵。
- [ ] 完成同条件 USB/WiFi 受控矩阵。
- [ ] 复测 Legacy OpenDisplay iOS/TestFlight Runtime。
- [ ] 完成双 Android 真机测试。
- [ ] 完成计划中的 30 分钟与 2 小时耐久测试。
- [ ] 在已连接接收端上重复断开/重连计时与旧 Connection Callback 压力测试。

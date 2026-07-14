[English](release-checklist.md) | [简体中文](release-checklist.zh-CN.md)

# `v0.2.0-preview.2` 发布检查清单

## 已发布身份

- Release：https://github.com/chenyuhao0628/displayweave/releases/tag/v0.2.0-preview.2
- 版本：`v0.2.0-preview.2`
- 单调递增 build/version code：`3`
- Release 目标提交：`adcc576f0b8667385b35ae04a76e8d5b9848c721`
- 公开更新源提交：`66d2dcfaa26297cc4e3cb7059e367a018eaa74ad`
- 成功的 Pages run：`29300403928`

## 产物与完整性

| 产物 | SHA-256 / 检查 |
| --- | --- |
| `DisplayWeave-macOS.zip` | `0c0bbd61625a90ef5264097da3f25db0d77c1383421e506a97aab0c6eb50b501` |
| `DisplayWeave-Android.apk` | `04a7433deb4fa893ef95f216d9b4e35e01ff5466bda56d801b88792b0122b2e1` |
| `DisplayWeave-Preview-0.1-iOS-unsigned-resigning-input.ipa` | `7a188576fec361daff62efbbb978f9800ae4fac55d269ffbfecb1806646289f4` |
| `appcast.xml` | `523252198c6bbd987281a9a60225576a53ba18e1f6421fbb2604be837868ec1f` |
| `android-update.json` | `25764708231ddcbc3f8eb7796a7ce8a9108ca10a9bee06665ccba2c49da09bd1` |
| `SHA256SUMS.txt` | 已存在并覆盖以上五个文件 |

Android 签名证书 SHA-256：

```text
89805f045800ea18b56b84b32e8e31b1710a3c7bf3c85fda54d260d1fc6d589d
```

- [x] Mac 应用为 universal ad-hoc 签名，并明确未公证。
- [x] Android APK 使用一个 signer、固定证书和 v2 签名。
- [x] iOS IPA 是未签名 arm64 自签输入包，不能直接安装。
- [x] Release 资产保持不可变；后续修正必须提高 build。

## 构建与自动验证

- [x] 17 项 Swift 测试通过。
- [x] 6 项 Android 自检通过。
- [x] Mac、iOS 兼容目标与 Android Release 构建完成。
- [x] 已检查归档结构、显示版本、build/version code、更新 URL、字节数、
  哈希、Android 包身份与签名。
- [x] 对应更新链路会拒绝无效 Sparkle 签名、被修改的 Android 下载、错误
  包身份与不递增版本。

## 更新渠道检查

- [x] 在线 Mac 更新源：
  https://chenyuhao0628.github.io/displayweave/appcast.xml
- [x] 在线 Android 更新源：
  https://chenyuhao0628.github.io/displayweave/android-update.json
- [x] Mac 首次安装说明披露了 Gatekeeper、ad-hoc 签名与未公证状态。
- [x] Android 首次安装说明披露了“安装未知应用”权限和系统强制确认；没有
  宣称静默安装。
- [x] 密钥丢失恢复与更新源回滚流程已写入[自动更新](automatic-updates.zh-CN.md)。

## iOS/OpenDisplay 兼容性

- [x] `_opensidecar._tcp` 发现与 TCP `9000` 端口保持不变。
- [x] 四字节长度前缀、Annex B H.264 与旧 hello 默认值继续可用。
- [x] Metal drawable 同步修复覆盖已报告的 iPhone 黑屏链路，不改变接收协议。
- [x] iOS 仍不属于 Mac/Android 自动更新渠道。

## 待补真机证据

- [ ] 完成双 Android 真机测试。
- [ ] 完成同条件 USB/WiFi 受控矩阵。
- [ ] 完成计划中的 30 分钟与 2 小时耐久测试。

[Preview 2 稳定性报告](stability-test-report.zh-CN.md)中的 OnePlus 高刷新/恢复
和 iPhone 观察仍是既有证据，本次发布没有重新执行。

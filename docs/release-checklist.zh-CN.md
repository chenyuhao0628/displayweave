[English](release-checklist.md) | [简体中文](release-checklist.zh-CN.md)

# `v0.2.0-preview.3` 发布检查清单

## 已发布身份

- Release：https://github.com/chenyuhao0628/displayweave/releases/tag/v0.2.0-preview.3
- 版本：`v0.2.0-preview.3`
- 单调递增 build/version code：`4`
- Release 目标提交：`1f159b44f256f64da53ae2c8cc3c1b96754bcad3`
- 公开更新源提交：`dbf730bd01d26df18a5717e34fb86d0b38b8809c`
- 成功的 Release run：`29323273404`
- 成功的 Pages run：`29323640794`

## 产物与完整性

| 产物 | SHA-256 / 检查 |
| --- | --- |
| `DisplayWeave-macOS.zip` | `32cade719d825d3f3562483cb72b9a4d65223e4b2518d54389ff2d661a1742ae` |
| `DisplayWeave-macOS.dmg` | `68b3737f09f8d02da135aef89167896aa4057d453d65fa20861e2ae58a142a29` |
| `DisplayWeave-Android.apk` | `98356346793932bd494a31585ff7ca788b880bd62cd6b8e2762aadc8ff0541c1` |
| `DisplayWeave-Preview-0.1-iOS-unsigned-resigning-input.ipa` | `7eb93eedd24e44bbabccb38ab145a2e2122e4c53bd52dbe8e9d2b3d08e21eb16` |
| `appcast.xml` | `3606e4f32678319f1bcea1e94e97bcba1a1171a6810ed935be3b00264f4795c8` |
| `android-update.json` | `90adbfe6345de384c8541b986673cae28c256a6cef8017e000fb93ff7cfdbf70` |
| `SHA256SUMS.txt` | 已存在并覆盖以上六个文件 |

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

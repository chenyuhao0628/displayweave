[English](release-notes-v0.2.0-preview.1.md) | [简体中文](release-notes-v0.2.0-preview.1.zh-CN.md)

# DisplayWeave `v0.2.0-preview.1` 发布说明

[GitHub prerelease](https://github.com/chenyuhao0628/displayweave/releases/tag/v0.2.0-preview.1)

## 主要改动

- Mac 新增使用应用内置 EdDSA 公钥认证的 Sparkle 更新，不要求 Apple
  Developer Program 账号；应用仍为 ad-hoc 签名且未公证。
- Android 新增回到前台时的每日检查，以及“设置与帮助”中的手动检查；
  下载通过验证后才会打开 Android 系统安装器。
- 更新提示、权限流程和取消安装不会再阻塞显示接收端恢复运行。
- Apple 接收端渲染链路会同步 Metal layer 与 drawable 大小，修复 iPhone
  连接后视频帧已经到达、画面却保持黑屏的问题。
- 现有 iOS/OpenDisplay 接收协议继续兼容。

## 一次性迁移

- **Mac：** 下载 `DisplayWeave-macOS.zip` 并核对校验和，然后手动替换
  `/Applications` 中的旧应用。Gatekeeper 可能要求按住 Control 点击并
  选择“打开”，或在“隐私与安全性”中选择“仍要打开”。后续版本可以使用
  已签名的 Sparkle 渠道。
- **Android：** 把 `DisplayWeave-Android.apk` 覆盖安装到现有
  `app.opendisplay.android` 包一次。后续更新可在应用内发现，但仍需
  “安装未知应用”权限和 Android 系统最终确认。
- **iOS/iPadOS：** 本版本仍提供未签名自签输入包，不能直接安装，也不属于
  自动更新渠道。

## 安全边界

- 如果 Mac 归档的 EdDSA 签名与已安装应用内置公钥不匹配，Sparkle 会拒绝
  更新。这能验证更新，但不能提供 Developer ID 签名或公证。
- Android 安装前会验证字节数、SHA-256、包名、递增版本号、最低 SDK 与
  固定签名证书。
- Release 资产保持不可变；修正必须发布更高 build 的新版本，不能替换现有
  下载。
- 本预览版的 WiFi 传输仍面向可信局域网，尚未加入加密配对。

## iOS 与 OpenDisplay 兼容性

Mac 保持 `_opensidecar._tcp` 发现、TCP `9000` 端口、四字节长度前缀、
Annex B H.264 视频和旧 hello 默认值。iOS 产物仍为
`DisplayWeave-Preview-0.1-iOS-unsigned-resigning-input.ipa`，因此现有兼容的
OpenDisplay 接收端可以继续连接。

## 产物与验证

| 文件 | SHA-256 或用途 |
| --- | --- |
| `DisplayWeave-macOS.zip` | `35c828abc9200affe8a63602519f63e56ca7aff4ca6a88d6bbcb2f2bf009bec5` |
| `DisplayWeave-Android.apk` | `24588906ccde36958355d8e72bae54fa1e6f8244c3fca832b81c9a05bd7519d9` |
| `DisplayWeave-Preview-0.1-iOS-unsigned-resigning-input.ipa` | `fee1b7d8c1b81bac33b91b11dfaeeb608ccc35050ccc4bcd796178227acdedfa` |
| `appcast.xml` | `efc966fd6f051417a6f06bf12fe31edca9d8728fa19ae730619e694a1df1d250` |
| `android-update.json` | `453c7e27ed3c261cfbca5f5bf1ba7c4d8861f7c0563cf8fc207254185176bf38` |
| `SHA256SUMS.txt` | 以上五个文件的校验清单 |

- Mac 更新源：https://chenyuhao0628.github.io/displayweave/appcast.xml
- Android 更新源：https://chenyuhao0628.github.io/displayweave/android-update.json
- Android 证书 SHA-256：
  `89805f045800ea18b56b84b32e8e31b1710a3c7bf3c85fda54d260d1fc6d589d`

本次发布验证覆盖 17 项 Swift 测试、6 项 Android 自检、Mac/iOS/Android
Release 构建、更新元数据一致性与篡改下载拒绝；同时检查了 GitHub Release、
Pages 部署和两个在线更新源。

## 待补证据

本预览版不宣称已经完成双 Android 真机、同条件 USB/WiFi 受控矩阵或计划中
的 30 分钟/2 小时耐久测试。Preview 2 稳定性报告中的 OnePlus 与 iPhone
观察仍是既有证据，本次发布没有重新执行。

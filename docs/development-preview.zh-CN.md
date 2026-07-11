[English](development-preview.md) | [简体中文](development-preview.zh-CN.md)

# DisplayWeave `v0.1.0-preview.2` 开发预览分发

- `DisplayWeave-Preview-0.1-macOS.zip`：ad-hoc 签名、未公证；核对来源与 SHA-256 后再处理 Gatekeeper。
- `DisplayWeave-Preview-0.1-Android.apk`：仓库外独立 keystore 的 v2 Release 签名，可侧载；首次安装前核对证书指纹。
- `DisplayWeave-Preview-0.1-iOS-unsigned-resigning-input.ipa`：未签名自签输入包，不能直接安装；用户必须提供自己的有效签名身份。
- `SHA256SUMS.txt`：三项 SHA-256。

运行 `./tools/package-preview-0.1.sh` 生成完整集合。Android keystore 位于 `~/Library/Application Support/DisplayWeave/Signing/`，密码存于 Keychain，均不得提交 Git。免费 Apple Personal Team 只适合维护者在已登记设备测试，不适合公开通用分发；项目不背书第三方签名服务。

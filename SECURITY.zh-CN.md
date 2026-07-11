[English](SECURITY.md) | [简体中文](SECURITY.zh-CN.md)

# 安全说明

## 支持范围

安全修复面向最新 `main` 与当前 Preview。Preview 属于开发产物，不承诺长期支持。

## 报告漏洞

请勿在公开 Issue 发布可利用漏洞。优先使用 `chenyuhao0628/displayweave` 的 GitHub 私密漏洞报告；不可用时，通过维护者 GitHub 资料中展示的方式私下联系。请提供受影响提交/版本、平台、前置条件、影响、复现步骤和可选缓解方案，不要收集无关屏幕内容或设备数据。

## 当前信任边界

- WiFi 视频与控制当前使用本地直连 TCP，尚无生产级加密或认证配对，只应在可信局域网使用。
- Android USB 需要 ADB RSA 授权，这会向 Mac 提供包括 shell/安装在内的广泛调试信任，不只限于 DisplayWeave；不用时请撤销 USB 调试授权。
- macOS Preview 使用 ad-hoc 签名且未公证，只从项目 Release 获取，并核对 `SHA256SUMS.txt`。
- Android Preview APK 使用项目离线密钥库签名；首次安装或更新前，核对发布检查清单中的 SHA-256 证书指纹。
- iOS 产物是未签名自签输入包，用户提供有效签名身份前不能安装或信任；第三方签名服务会引入独立风险。
- 屏幕录制、辅助功能输入注入、本地网络和 USB 调试权限都很强大。只授予当前传输所需权限，测试后撤销。
- `CGVirtualDisplay` 是私有 API，平台更新可能改变隔离或行为。

## 敏感材料

不得提交 Android keystore/密码、Apple 证书私钥、含私密材料的 provisioning profile、私人日志中的设备标识或用户屏幕截图。发布脚本把 Android keystore 保存在仓库外，并从 Keychain 读取密码。

## 发布验证

按照 [docs/release-checklist.zh-CN.md](docs/release-checklist.zh-CN.md) 执行。有效 Preview 发布必须完成源码/构建检查、APK v2 验证、macOS bundle 验证、IPA 归档卫生和 SHA-256 验证。

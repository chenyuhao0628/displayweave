[English](release-notes-preview-0.1.md) | [简体中文](release-notes-preview-0.1.zh-CN.md)

# DisplayWeave `v0.1.0-preview.2` 发布说明

Preview 2 将 Android USB 从“已实现”推进到经过真机验证的开发预览，并独立打包 Mac、Android 与 iOS 自签输入产物。

## 重点

- Android USB 为每个有线 serial 使用独立动态 Mac 本地 `adb forward`。
- Auto 优先 USB，执行有限恢复，只回退到同 install ID WiFi，并在不让两个会话争抢 Android 接收端的前提下升级回 USB。
- 无线调试 ADB 端点不会生成伪 USB 会话。
- 修复 Android Surface/前台返回、streamConfig 恢复与协议级重连就绪判断。
- 已验证 OnePlus USB HEVC/120、H.264/60、触摸、双指滚动、线缆拔插、ADB 重启、取消/恢复授权及 WiFi 回退。
- 当前 DisplayWeave iPhone WiFi 与一台 Android 可并发运行。
- Android 使用离线 v2 签名 Release APK 分发。

## 产物

- `DisplayWeave-Preview-0.1-macOS.zip`——通用 ad-hoc 签名，未使用 Developer ID 且未公证。
- `DisplayWeave-Preview-0.1-Android.apk`——项目离线签名 Release APK。
- `DisplayWeave-Preview-0.1-iOS-unsigned-resigning-input.ipa`——未签名输入包，不能直接安装。
- `SHA256SUMS.txt`——全部产物 SHA-256。

## 证据边界

现有 OnePlus HEVC/120 WiFi 结果仍为约 109–111 渲染 FPS，不保证稳定满 120 FPS。双 Android 并发、同条件 USB/WiFi 受控 Benchmark 与 30 分钟/2 小时耐久测试延后。当前 WiFi TCP 尚未生产级加密，请使用可信局域网。

参见[发布检查清单](release-checklist.zh-CN.md)和[稳定性报告](stability-test-report.zh-CN.md)。

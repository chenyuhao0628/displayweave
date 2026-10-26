[English](SUPPORT.md) | [简体中文](SUPPORT.zh-CN.md)

# 支持与问题反馈

v0.3.1 的入口为[当前下载](docs/releases/current.zh-CN.md)、[配对指南](docs/guides/secure-transport.zh-CN.md)与[文档导航](docs/README.zh-CN.md)。按用途检查屏幕录制、输入回传需要的辅助功能以及本地网络权限。接收端保持前台；局域网连接检查是否处于同一网络、多播发现和 VPN／过滤器影响。

## 提供可复现的问题

记录两端版本／构建号、设备型号与系统、发送／接收角色、镜像／扩展、LAN 或 USB、所选分辨率／编码／帧率／码率、目标与实测 FPS、复现步骤及恢复行为。附必要且脱敏的日志或崩溃文字。不要附上配对邀请、私钥、设备标识或包含私人内容的完整屏幕截图。

Android 同时支持局域网和有线 ADB-forward USB。USB 问题请说明是否处于已授权 `device` 状态、是否使用数据线、重新连接后的表现。无线调试不属于有线 USB 会话。画面比例／触控问题请说明旋转、黑边和触摸区域。

## 已知边界

Wi-Fi 表现取决于网络条件。静态桌面可能产生较少帧，不等于连接中断。Mac-to-Mac、高刷、真实 Pencil／Intel／多设备性能和耐久仍需更广泛实机验收。Mac v0.3.1 使用 Apple Development 签名且未公证；iOS 需要个人签名，可能需要重新配置。详见[发布验证与限制](docs/releases/v0.3.1.zh-CN.md)和 [Mac 权限恢复](docs/guides/mac-permissions.zh-CN.md)。

[English](https://github.com/chenyuhao0628/displayweave/blob/main/docs/release-notes-v0.2.1-p3.md) | [简体中文](https://github.com/chenyuhao0628/displayweave/blob/main/docs/release-notes-v0.2.1-p3.zh-CN.md)

# DisplayWeave `v0.2.1-p3` 发布说明

DisplayWeave 0.2.1-p3 改进 macOS 与 Android 的高刷新串流和连接恢复。

## 改动

- 分离 VideoToolbox 异步编码工作与 Socket 发送背压，避免把 90/120fps 采集错误限制在约 60fps。
- 在串流配置中正确标记当前使用的 USB 或 WiFi 传输。
- “连接”按钮会按照当前选择的传输模式使用对应设备目标。
- 重连前回收 DisplayWeave 自有的过期 ADB Forward，并避免 Android 主线程断开连接时阻塞写入 WiFi。
- 扩大并统一 Android 服务端/解码器的有界帧队列，以吸收短时调度和传输突发。
- 动画性能测试图案仅在 Debug 构建中编译；Release 产物只保留空操作接口。

## 验证

- 22 套 macOS 独立 Self Test 全部通过。
- macOS Release 的 arm64 与 x86_64 构建通过。
- Release 二进制审计未发现动画测试 View、相关日志字符串或 CoreVideo Display Link 入口。
- 已在现有 OnePlus Android 真机覆盖 USB/WiFi、H.264/HEVC 和 60/90/120fps 测试。
- `git diff --check` 通过。

高刷新性能仍取决于设备与网络条件；WiFi 参考链恢复仍可能造成短时帧率下降。

## SHA-256

- Android APK：`99bdedb0743eb34cc7d2cb94aaa4141e8d9542e0fd4a42460ae46fccc4904004`
- macOS ZIP：`d925d89c4cae6db1723abedf322afd97d414a9c2f985a64516b647a1669b7a01`
- macOS DMG：`4d375d6cb50d5a99420a564c7f0e6f1b2231e6b67e58a4efd78d12db5b512c1e`
- iOS 未签名自签输入包：`90c971ff0837a401563a48cabfa594e86aa0ff02b513d24996a109123a5a4949`
- Sparkle Appcast：`5fb508cb5dd8cfc9f4f3f01db2c799c7f9f441b5fdc1315c281e12604bb2c5a3`
- Android 更新清单：`ede2c36c2f5b01fba62ae29412373d5ccda4882c6598242bb40f85b1185fbef8`

[English](https://github.com/chenyuhao0628/displayweave/blob/main/docs/release-notes-v0.2.1-p3.md) | [简体中文](https://github.com/chenyuhao0628/displayweave/blob/main/docs/release-notes-v0.2.1-p3.zh-CN.md)

# DisplayWeave `v0.2.1-p3` 发布说明

DisplayWeave 0.2.1-p3 改进 macOS 与 Android 的高刷新串流和连接恢复。

## 改动

- 分离 VideoToolbox 异步编码工作与 Socket 发送背压，避免把 90/120fps 采集错误限制在约 60fps。
- 在串流配置中正确标记当前使用的 USB 或 WiFi 传输。
- “连接”按钮会按照当前选择的传输模式使用对应设备目标。
- 重连前回收 DisplayWeave 自有的过期 ADB Forward，并避免 Android 主线程断开连接时阻塞写入 WiFi。
- 动画性能测试图案仅在 Debug 构建中编译；Release 产物只保留空操作接口。

## 验证

- 22 套 macOS 独立 Self Test 全部通过。
- macOS Release 的 arm64 与 x86_64 构建通过。
- Release 二进制审计未发现动画测试 View、相关日志字符串或 CoreVideo Display Link 入口。
- 已在现有 OnePlus Android 真机覆盖 USB/WiFi、H.264/HEVC 和 60/90/120fps 测试。
- `git diff --check` 通过。

高刷新性能仍取决于设备与网络条件；WiFi 参考链恢复仍可能造成短时帧率下降。

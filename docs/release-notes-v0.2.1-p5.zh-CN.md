[English](https://github.com/chenyuhao0628/displayweave/blob/main/docs/release-notes-v0.2.1-p5.md) | [简体中文](https://github.com/chenyuhao0628/displayweave/blob/main/docs/release-notes-v0.2.1-p5.zh-CN.md)

# DisplayWeave `v0.2.1-p5` 发布说明

DisplayWeave 0.2.1-p5 加固 Android 对异常 H.264 配置数据的处理，并消除两端在重连资源清理过程中的跨线程竞态。

## 改动

- 对截断、溢出或无效的 H.264 SPS 数据执行可控的解码器恢复，避免 Android 解码工作线程退出。
- Android 最新帧工作线程发生运行时解码异常后，保证恢复为空闲状态或重新调度。
- 提交协议状态前先校验串流配置，并记录此前被静默忽略的控制消息异常。
- 确保 Mac 时钟偏移量的跨线程可见性，并在换算触控时间戳前读取一次快照。
- 在停止和旋转重建期间，串行化 Mac 捕获、编码器、串流及虚拟显示器的清理状态。
- 在附加 H.264/H.265 参数集时统一使用同一个关键帧判断逻辑。
- 为异常 SPS 输入与解码工作线程恢复增加确定性回归测试。

## 验证

- 22 套 macOS 独立 Self Test 全部通过。
- Android 单元测试与 Debug APK 构建通过。
- macOS Debug App 的 Xcode 构建通过。
- `git diff --check` 通过。

macOS App 仍采用 Ad-hoc 签名且未公证；Android 使用固定的 DisplayWeave Release 证书签名。本补丁未重新执行 WiFi 与 USB 真机重连验证。

## SHA-256

- Android APK：`283b27a593063047a810c2cf9de255f64e87f0e7eb50e79701488b7bcfb46f22`
- macOS ZIP：`331faad563cf81c3e9582246d7a1d283a6c388bdd3dc339d28e7454694dc2fc8`
- macOS DMG：`b6454ff3b62aeb4cb2d2af644424a3c9ae63061ce4ff10df4c3a071c9056d61a`
- iOS 未签名自签输入包：`2ca4b21359c30ea0d604e2d5a9747dc4aa315610fa86e8b131afe1ef03da26a0`
- Sparkle Appcast：`3bc5becfd6d2e4c1e5321acc231e9b25cca5404592a40d0371b651f3308a12c9`
- Android 更新清单：`61da584c4b78ff0e2f2eb8292a60fbc6a732bfa49bbd2f989c0aaee2c4f22d1b`

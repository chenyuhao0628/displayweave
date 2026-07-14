[English](release-notes-v0.2.1.md) | [简体中文](release-notes-v0.2.1.zh-CN.md)

# DisplayWeave `v0.2.1` 发布说明

DisplayWeave 0.2.1 重点改进连接与解码器生命周期正确性、有限恢复和可复现的发布验证。

## 主要变化

- 使用独立 Connection Generation 与当前对象校验隔离每一个 Mac `NWConnection` 回调。
- 合并延迟 Reconnect，在 Ready 或停止时取消，并拒绝过期重连任务。
- 把断线宽限锚定到最后一次 Peer 活动，使虚拟显示器在声明的约 10 秒截止时间清理，而不是叠加两段超时。
- 按 Decoder Generation 隔离 Android 异步 `MediaCodec` 回调，严格管理 Input Buffer 所有权，并限制 Rendered-frame Telemetry 容量。
- 识别包括 CRA 在内的 HEVC IRAP 恢复帧，并合并终止 Decoder 恢复。
- 按 Encoder Generation 隔离 Mac 异步编码工作，拒绝旧或重复 Completion。
- 使 Android 广告 Decoder FPS 与实际选中的 Decoder 及其 H.264 回退路径一致。
- 把 GC 指标改为可复位的窗口增量，并新增 Android、Mac、iOS 兼容构建、网站、文档和发布契约 CI。

## 验证

- 22 组 Swift Standalone Suite 通过。
- Android Clean Test 与 Debug Assembly 通过，包括全部六组 Self-test。
- macOS Debug 与未签名 iOS Simulator 兼容构建通过。
- 网站、双语文档、发布链接、Workflow 语法和空白检查通过。

没有设备可用的 WiFi/USB、Codec、刷新率、恢复、耐久与 Legacy Receiver 真机验证仍保持 Pending。Mac 应用仍为 ad-hoc 签名且未经过 Apple 公证；安装前请核对发布校验和。


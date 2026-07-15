[English](https://github.com/chenyuhao0628/displayweave/blob/main/docs/release-notes-v0.2.1-p1.md) | [简体中文](https://github.com/chenyuhao0628/displayweave/blob/main/docs/release-notes-v0.2.1-p1.zh-CN.md)

# DisplayWeave `v0.2.1-p1` 发布说明

DisplayWeave 0.2.1-p1 是针对 Android 异步解码、参考链恢复、Mac 异步任务隔离和 USB 码率归因的修正更新。

## 主要改进

- 将 Android 服务端与 `MediaCodec` 的单帧 Pending Slot 改为小型有序队列，短暂 Input Buffer 压力不再立即破坏预测参考链。
- 仅在预测帧确实丢失后进入关键帧恢复；清除不安全的排队帧、合并恢复请求，并将等待关键帧期间拒绝的帧与首次参考链断裂分开统计。
- 新增端到端接收端计数：接收、提交、解码、渲染帧数，以及队列替换、恢复持续时间、关键帧请求和接收次数，并导出到 Mac Benchmark。
- 上报实际成功配置的 Decoder 最大 FPS；若运行时回退 Decoder 低于先前广告能力，Mac 会重新协商捕获帧率。
- 使用 Encoder Generation 与唯一 Work ID 跟踪 VideoToolbox 任务，旧回调或重复 Completion 不再污染当前 Pending Encode 预算。
- 暴露 Pending Encode、Pending Send、联合工作量和 Pending Encode 峰值，同时保持旧 Queue Depth 字段语义不变。
- USB Auto 使用独立码率估算。原生 3040×1904、120fps、High、HEVC 初始约 112 Mbps，稳定后可向 USB 160 Mbps 上限恢复。
- USB 不再把编码端 Capture Skip、FPS 统计窗口错位、RTT 或 Frame Age 短时波动误判为物理链路拥塞；真实 Pending Send 与持续 Android 解码压力仍会保护性降码。

## 验证

- 全部独立 Swift 测试通过。
- Android Clean Test、Debug/Release 编译和六组 Self Test 全部通过。
- macOS Debug 构建成功。
- 发布前网站、中英文文档、Release Contract 与空白检查通过。
- OnePlus OPD2413 通过 ADB USB、HEVC 3040×1904、请求 120fps 的修复后真机窗口记录到接收/提交/解码/渲染分别为 72/72/72/72、75/75/75/75、76/76/76/76 和 81/81/80/80；这些窗口的 Pending Slot Replace、Reference Chain Break、恢复持续时间与关键帧请求均为零。

上述配置已获得 Android 高刷新恢复的真机证据。新的 USB 码率策略已通过策略测试和构建验证，但同场景 USB/WiFi 受控码率矩阵仍待完成。Mac 应用仍为 Ad-hoc 签名，未经过 Apple 公证。

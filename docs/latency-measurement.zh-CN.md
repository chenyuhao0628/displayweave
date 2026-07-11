[English](latency-measurement.md) | [简体中文](latency-measurement.zh-CN.md)

# 延迟测量

DisplayWeave 把延迟分为真实测量阶段与明确标记的估算值，不声称已经测得 photon-to-photon latency。

## 时间线

| 时间戳 | 时钟 / 当前状态 | 含义 |
| --- | --- | --- |
| `captureTimestamp` | Mac wall clock；当前在 encoder 入口采样 | 捕获帧进入编码路径，尚不是精确的 SCStream callback 边界 |
| `encoderSubmitTimestamp` | Mac monotonic 目标字段 | 调用 `VTCompressionSessionEncodeFrame` 前 |
| `encoderOutputTimestamp` | Mac monotonic 目标字段 | VideoToolbox completion 产生编码输出 |
| `socketSendTimestamp` | 当前为 Mac wall clock | 编码 payload 交给 framed socket 路径 |
| `androidReceiveTimestamp` | 当前为 Android wall clock | Receiver 收到完整 framed payload |
| `decoderSubmitTimestamp` | Android monotonic 目标字段 | 帧排入 MediaCodec |
| `decoderOutputTimestamp` | Android monotonic 目标字段 | MediaCodec output 可用 |
| `renderTimestamp` | 当前为 Android wall clock | MediaCodec render callback；不代表光子扫描完成 |

“目标字段”表示隔离该阶段所必需、但目前尚未独立导出的时间戳。时间戳缺失时字段必须不可用，不得反推补造。

## 指标定义

- **Encode API latency：** VideoToolbox 提交前到 completion 的 Mac 时间，不包含 ScreenCaptureKit 等待。
- **Network transit estimate：** clock offset 稳定后计算 `androidReceive - socketSend`；包含 framing 与 transport 调度，时钟 estimating 时不可用。
- **MediaCodec latency：** 同一 Android monotonic clock 上的 decoder submit 到 output；它是目标字段，旧“decode latency”实际是 send-to-render。
- **Render delay：** Android decoder output 到 render callback，不包含面板扫描。
- **Receive-to-render Frame Age：** 同一 Android 时钟上的 receive 到 render，导出 average、latest、P50、P95、P99。
- **Estimated E2E：** clock correction 后从 Mac capture/encoder-entry 到 Android render，只用于同条件相对比较，不作为绝对光子延迟。
- **Input P50/P95：** Android control-message send 估算到 Mac `CGEvent.post`，不包含发送前的触摸采样和 post 后的视觉响应。

## 时钟同步

Android 发送 `t1`；Mac 记录 receive `mr` 和 send `ms`，同时保留旧字段 `mt`；Android 记录 `t2`。每个四时间戳样本：

`RTT = (t2 - t1) - (ms - mr)`

`offset = ((mr - t1) + (ms - t2)) / 2`

Receiver 保存有界多样本窗口，拒绝负 RTT 或超过 250 ms 的 RTT，选择最低 RTT 的一半样本并取 offset median。Confidence 是所选 RTT spread 的一半。少于 3 个有效样本时状态为 `estimating`；缺失或被拒绝时不可用。Estimator stable 前，跨时钟 E2E 与 send-to-render 必须为 JSON `null` / CSV `notAvailable`。

两端跨设备帧标记仍使用 wall timestamp；系统校时和路径不对称会造成偏差。Confidence 只是 uncertainty signal，不保证绝对准确或传输路径对称。

## Benchmark 解读

Clock state 未稳定时优先使用单时钟 Frame Age 与 rendered FPS。稳定后，也只比较 RTT/confidence 接近且条件相同的 run 的 E2E 分布。不得用 RTT 或零替代缺失的 decode、input、CPU、thermal 数据。只有 mean 而没有 P95 不足以得出延迟结论。

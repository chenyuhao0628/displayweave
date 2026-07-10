# Android USB vs WiFi Benchmark

状态：**待真机执行**（2026-07-11 自动探测时 `adb devices -l` 没有列出设备）。

本文是 DisplayWeave Preview 0.1 的受控 Benchmark 记录。不得把未执行项目写成通过，也不预设 USB 一定提高 FPS。

## 固定测试条件

同一轮 WiFi/USB 比较必须使用同一台 Mac、同一台 Android、同一分辨率、同一 HEVC codec、同一 120fps 请求、同一码率和同一测试画面。先执行 10 分钟基础测试，再执行 30 分钟稳定性测试。测试内容应持续变化，避免 ScreenCaptureKit 因静态画面减少输出。

| 条件 | WiFi | USB |
| --- | --- | --- |
| Mac 型号 / macOS | 待记录 | 与 WiFi 相同 |
| Android 型号 / 系统 / SDK | 待记录 | 与 WiFi 相同 |
| DisplayWeave commit | 待记录 | 与 WiFi 相同 |
| 分辨率 | 待记录 | 与 WiFi 相同 |
| codec / profile | HEVC / 待记录 | 与 WiFi 相同 |
| 请求 FPS | 120 | 120 |
| 固定码率 | 待记录 | 与 WiFi 相同 |
| 测试内容 | 待记录 | 与 WiFi 相同 |
| 运行时间 | 10 分钟 + 30 分钟 | 10 分钟 + 30 分钟 |

## 结果

当前没有连接 Android 真机，因此下表全部为“待人工验证”，没有填入推测值。

| 指标 | WiFi 10 min | USB 10 min | WiFi 30 min | USB 30 min |
| --- | ---: | ---: | ---: | ---: |
| captureFps | 待验证 | 待验证 | 待验证 | 待验证 |
| encodedFps | 待验证 | 待验证 | 待验证 | 待验证 |
| sentFps | 待验证 | 待验证 | 待验证 | 待验证 |
| receivedFps | 待验证 | 待验证 | 待验证 | 待验证 |
| decodedFps | 待验证 | 待验证 | 待验证 | 待验证 |
| renderedFps | 待验证 | 待验证 | 待验证 | 待验证 |
| averageFps | 待验证 | 待验证 | 待验证 | 待验证 |
| 1% low FPS | 待验证 | 待验证 | 待验证 | 待验证 |
| minimumFps | 待验证 | 待验证 | 待验证 | 待验证 |
| bitrate | 待验证 | 待验证 | 待验证 | 待验证 |
| encodeLatency | 待验证 | 待验证 | 待验证 | 待验证 |
| decodeLatency | 待验证 | 待验证 | 待验证 | 待验证 |
| estimatedE2ELatency | 待验证 | 待验证 | 待验证 | 待验证 |
| latestFrameAge | 待验证 | 待验证 | 待验证 | 待验证 |
| queueDepthMac | 待验证 | 待验证 | 待验证 | 待验证 |
| queueDepthAndroid | 待验证 | 待验证 | 待验证 | 待验证 |
| droppedFramesMac | 待验证 | 待验证 | 待验证 | 待验证 |
| droppedFramesAndroid | 待验证 | 待验证 | 待验证 | 待验证 |
| reconnectTime | 待验证 | 待验证 | 待验证 | 待验证 |
| Mac CPU / memory | 待验证 | 待验证 | 待验证 | 待验证 |
| Android CPU / memory | 待验证 | 待验证 | 待验证 | 待验证 |

## 执行步骤

1. 冷启动 Mac Sender 与 Android Receiver，记录版本、设备和环境。
2. Transport 选择 WiFi，固定分辨率、HEVC、120fps 与码率。
3. 运行同一测试内容 10 分钟，导出全链路统计；再独立运行 30 分钟。
4. 停止会话并确认队列、虚拟显示和 socket 清理。
5. Transport 选择 USB；确认 `adb -s <serial> forward --list` 只有该 session 的动态映射。
6. 使用完全相同条件重复 10 分钟与 30 分钟测试。
7. 计算 average、minimum 和 1% low；保存原始日志位置与 SHA-256。
8. 比较平均值、波动、延迟、队列和丢帧。若 USB 只降低延迟或波动，应如实写明平均 FPS 没有提高。

## 已有但不可代替本测试的证据

OnePlus OPD2413 的历史 HEVC/120 WiFi 真机结果约为 109–111 FPS，记录在 `docs/120hz-migration-plan.md`。该结果证明既有 WiFi 高刷新链路，不构成 USB 性能证据，也不能作为本表的 USB 对照数据。


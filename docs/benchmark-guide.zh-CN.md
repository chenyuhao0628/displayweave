[English](benchmark-guide.md) | [简体中文](benchmark-guide.zh-CN.md)

# 短时 Benchmark 指南

DisplayWeave 的 Debug-only Short Benchmark 只记录 Sender 与 Receiver 的真实样本，不会自动拖动窗口、滚动浏览器、切换 Transport，也不会补造缺失样本。操作者负责执行指定场景，并保留所有中止或失败的 run。

## Run 格式

1. 只连接一个 Receiver，等待温度与供电状态稳定。
2. 固定 commit、Mac、Receiver、分辨率、scale、codec、请求 FPS、目标码率、transport、场景和起始温度；每次只改变一个主要变量。
3. 在 **Short Benchmark (Experimental)** 中选择场景和时长并开始记录。
4. 在 30 秒 `warmup` 和随后选定的 `run` 阶段持续执行同一场景。
5. Frame Age 或队列持续增长、设备降频、画面失败或测试条件改变时立即停止。保留输出并标注原因，不得删除不利样本。

时长：

| 模式 | 预热 | 正式记录 | 用途 |
| --- | ---: | ---: | --- |
| Standard | 30 秒 | 3 分钟 | 必需的短时对比 |
| Extended | 30 秒 | 5 分钟 | 本地工程检查 |
| Optional | 30 秒 | 10 分钟 | 单次本地测试上限 |

每个受控组合至少运行 2 次，条件允许时运行第 3 次。本轮不要求 30 分钟或 2 小时耐久测试。

## 场景

- **Static Desktop：** 固定桌面与窗口；ScreenCaptureKit 由内容变化驱动，完全静止时 capture FPS 自然下降。
- **Text Scroll：** 使用同一文档、视口、字号和可重复滚动轨迹。
- **Browser Scroll：** 使用固定本地页面和可重复滚动轨迹，避免网络加载内容。
- **120Hz MTKView Test Pattern：** 固定图案、动画频率、窗口大小和显示位置。
- **Rapid Window Drag：** 固定窗口、路径、速度和持续时间。

## 受控参数矩阵

- 分辨率：`1920×1080`、`2560×1600`、Android 原生分辨率。
- Codec：HEVC、H.264。
- 请求频率：Receiver 声明支持时使用 60、90、120 FPS。
- Transport：WiFi、USB。

不要求不受硬件支持的笛卡尔积组合。应把不支持或不可用如实记录，不得在不修改 run metadata 的情况下替换测试条件。

## 输出

每个 run 写入：

`~/Library/Application Support/DisplayWeave/Benchmarks/<run-id>/`

- `benchmark.csv`：RFC 4180 字段、CRLF 行结束；不可用值写 `notAvailable`。
- `benchmark.jsonl`：每个样本一个 JSON object；不可用的可选数值指标写 `null`，必填 metadata 使用 `notAvailable` 等明确 fallback。

两种文件都包含 `runId`、`sessionId`、`scene`、`phase`、wall `timestamp` 和 monotonic elapsed milliseconds。Schema 记录：

- device model、transport、codec、width、height、requested FPS；
- Mac 虚拟显示器和 Android 屏幕的实际刷新率；
- capture、encoded、sent、received、decoded、rendered FPS；
- target bitrate、actual wire bitrate、平均编码帧大小；
- encode API latency、send-to-render estimate、RTT、clock offset、offset confidence/state；
- Frame Age average/latest/P50/P95/P99 和 estimated E2E；
- pending sends、Mac/Android queue depth 和 drops；
- input P50/P95、Mac CPU、Mac memory。

Producer 不可用不等于零：CSV 使用 `notAvailable`；JSONL 的可选指标使用 `null`，必填 metadata 使用明确的 fallback 字符串。由于尚无可信的区间采样器，Mac CPU 当前保持不可用。停止的 run 保留已经 flush 的样本；flush 失败会连同输出路径显示，必须视为失败证据。

## 对比方法

使用匹配 run 的 median 和 P95，不挑选单个有利瞬间。当前文件可对比 rendered FPS、Frame Age 分布、RTT、队列快照和 Mac/Android aggregate drops。Target Bitrate 与 Actual Bitrate 必须分列；更高码率是画质变量，不是更低延迟的证据。分类 drop 原因、关键帧事件、1% low 聚合和视觉稳定性尚不是 recorder 字段，应另行计算或人工标注；未观察时必须写不可用。

现有设备上的 3 分钟 USB/WiFi A/B 矩阵仍待真实执行。Recorder 已存在不代表 Benchmark 已完成。

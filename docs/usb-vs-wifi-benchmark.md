[English](usb-vs-wifi-benchmark.md) | [简体中文](usb-vs-wifi-benchmark.zh-CN.md)

# Android USB vs WiFi Benchmark

状态：**受控对比待执行**。本文按《DisplayWeave 下一阶段优化计划（低延迟 + 高刷新率 + 高码率）》建立测量协议；已有约 11 分钟 USB 观察因内容和配置变化，只作为功能证据，不进入对照结果。

## 核心原则

- 使用同一台 Mac、同一台 Android、同一 commit、同一分辨率、codec、请求刷新率、固定码率和测试内容。
- 每个场景先 WiFi、再 USB；第二轮反转顺序，降低温度和缓存偏差。
- 预热 2 分钟后采样 10 分钟。30 分钟稳定性和 2 小时耐久由用户另行执行并追加结果。
- 测试时禁用 Auto bitrate；一次只改变 transport。请求 120fps 不代表实际 120Hz。
- 同时保存 Mac 与 Android 原始统计、系统信息、日志和 SHA-256，不用肉眼印象代替数据。

## 固定环境记录

| 字段 | 值 |
| --- | --- |
| Mac 型号 / macOS / 电源模式 | 待记录 |
| Android 型号 / 系统 / SDK / 显示模式 | 待记录 |
| DisplayWeave commit / 构建类型 | 待记录 |
| 分辨率 / 缩放 | 待记录 |
| codec / profile | HEVC / 待记录 |
| requested / actual refresh rate | 120 / 待记录 |
| 固定码率 | 待记录；WiFi 与 USB 相同 |
| WiFi 频段 / 信号 / AP | 待记录 |
| USB 线材 / 端口 / 协议 | 待记录 |
| 屏幕亮度 / 温度起点 / 后台应用 | 待记录并固定 |

## 四个测试场景

1. **桌面静态**：固定桌面与轻量光标移动；观察静态内容下 frame age、码率和内容驱动降帧，不用低 capture FPS 误判链路能力。
2. **浏览器滚动**：使用固定本地页面和自动滚动轨迹；记录 FPS、frame age、RTT、queue 和 dropped frames。
3. **4K60 视频**：使用同一本地 4K60 测试片源，避免网络视频波动；记录 capture、encode、receive、decode、render FPS。
4. **高动态/游戏输入**：使用可复现 demo 或固定回放；记录 frame age、queue depth、drops。Input latency 若无高速相机，只标“未测量”，不可用 RTT 代替。

每个场景执行 `WiFi A -> USB A -> 冷却/重启 -> USB B -> WiFi B`。报告 A/B 两轮及合并分布，不只报告最好一次。

## 采样字段

推荐每秒一行 CSV，字段如下：

```text
timestamp,run_id,scene,transport,codec,width,height,requested_hz,actual_hz,target_bitrate_mbps,capture_fps,encode_fps,sent_fps,receive_fps,decode_fps,render_fps,actual_bitrate_mbps,encode_latency_ms,estimated_e2e_latency_ms,latest_frame_age_ms,rtt_ms,queue_depth_mac,queue_depth_android,dropped_mac_total,dropped_android_total,reconnect_count,mac_cpu_pct,mac_memory_mb,android_cpu_pct,android_memory_mb,android_temperature_c
```

断线事件另存事件表：

```text
timestamp,run_id,event,serial_or_install_id,local_port,peer_ready_ms,first_frame_ms,reason
```

`peer_ready_ms` 从断开到收到新 peer 控制消息，`first_frame_ms` 从断开到首个成功渲染帧；二者不可混写。

## 汇总结果模板

当前没有满足固定条件的成对数据，全部保持待验证。

| 场景 / 指标 | WiFi 10 min | USB 10 min | USB 相对变化 |
| --- | ---: | ---: | ---: |
| 桌面静态 frame age P50/P95/P99 | 待验证 | 待验证 | 待计算 |
| 浏览器滚动 render FPS avg / 1% low / min | 待验证 | 待验证 | 待计算 |
| 浏览器滚动 drops / queue P95 | 待验证 | 待验证 | 待计算 |
| 4K60 capture/encode/render FPS | 待验证 | 待验证 | 待计算 |
| 高动态 frame age P50/P95/P99 | 待验证 | 待验证 | 待计算 |
| RTT P50/P95/P99 | 待验证 | 待验证 | 待计算 |
| actual bitrate avg/P95 | 待验证 | 待验证 | 待计算 |
| reconnect peer-ready / first-frame | 待验证 | 待验证 | 待计算 |
| CPU / memory / peak temperature | 待验证 | 待验证 | 待计算 |

## 分析规则与停止条件

- FPS 同时报 average、1% low 和 minimum；延迟、frame age、RTT 与 queue 报 P50/P95/P99。
- dropped frame 使用区间增量，不比较累计计数器的绝对值。
- USB 若只改善 P95/P99、抖动或恢复时间，应明确写“平均 FPS 无显著提升”。
- 任一设备明显降频、温度超过设备安全策略、frame age 持续上升或队列持续 `>= 2` 时停止高码率实验并保留失败数据。
- 历史 OnePlus WiFi HEVC/120 约 109–111 FPS 只证明旧环境能力，不能充当本轮 USB 对照。

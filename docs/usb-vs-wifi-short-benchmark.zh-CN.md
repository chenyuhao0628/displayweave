# USB 与 WiFi 短时 Benchmark

状态：等待当前 OPD2413 获得有效屏幕捕获权限并完成测试。

必测矩阵为 HEVC 60/90/120 与 H.264 60；Mac、设备、分辨率、codec、FPS、目标码率、场景和时长必须相同。每种传输先预热 30 秒，再记录三分钟，至少重复两次。

报告必须比较平均/1% Low FPS、平均/P95 Frame Age、RTT、抖动、丢帧、队列深度、Target/Actual Bitrate 和视觉稳定性。有效 CSV/JSONL 证据产生前不记录传输结论。

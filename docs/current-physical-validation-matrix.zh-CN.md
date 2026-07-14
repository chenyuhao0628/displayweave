[English](current-physical-validation-matrix.md) | [简体中文](current-physical-validation-matrix.zh-CN.md)

# 当前真机验证矩阵

2026-07-15 状态：`adb devices -l` 没有已连接设备。不得根据源码或自动测试推断运行结果。

| Transport | Codec | FPS | 状态 |
| --- | --- | --- | --- |
| WiFi | H.264 | 60 | Pending |
| WiFi | HEVC | 60 | Pending |
| WiFi | HEVC | 设备支持时 90/120 | Pending |
| USB | H.264 | 60 | Pending |
| USB | HEVC | 60 | Pending |
| USB | HEVC | 设备支持时 90/120 | Pending |

全部恢复场景（USB 拔插/快速拔插、ADB 重启/授权、前后台、锁屏、Surface 重建、WiFi 恢复、Auto Transport 切换、Codec 回退、连续重连、半断开 Socket 接管）均为 Pending。

后续每个矩阵单元需要 30 秒预热、至少两次且每次三分钟、每次只改变一个主要变量，并记录任务书要求的全部指标。Legacy iOS/旧 Android 真机兼容同样 Pending；实际运行前只能报告 Protocol-level Compatibility。

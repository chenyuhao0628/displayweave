[English](roadmap-and-acceptance.md) | [简体中文](roadmap-and-acceptance.zh-CN.md)

# DisplayWeave 开发与验收目标

状态分为已验证、实验性、待完成。Preview 2 已验证 Android 动态 ADB USB、Auto 同 install ID 回退/升级、生命周期重连、OnePlus USB HEVC/120 与 H.264/60、输入、授权/拔插/ADB 恢复、离线签名 APK 和当前 iPhone/Android 并发。

Android 高刷新保持实验性：OnePlus HEVC/120 WiFi 约 109–111 渲染 FPS，不承诺其他设备稳定 120 FPS。macOS 私有 `CGVirtualDisplay` 与未加密 WiFi 也属于明确风险边界。

待完成验收：两台 Android 独立 serial/port/session、同分辨率/codec/码率/温度的 USB/WiFi Benchmark、30 分钟和 2 小时耐久、iOS/iPadOS 120Hz、加密配对及生产签名分发。

任何状态升级都需要可复现构建、明确硬件/系统/配置、通过自动检查、记录失败恢复与性能指标，并同步更新中英文说明。

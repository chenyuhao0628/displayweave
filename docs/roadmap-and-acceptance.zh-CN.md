[English](roadmap-and-acceptance.md) | [简体中文](roadmap-and-acceptance.zh-CN.md)

# 开发与验收

[路线图](../ROADMAP.zh-CN.md)与[功能台账](feature-completion.zh-CN.md)记录 v0.3.0-preview.1（16）实现及验证。加密配对、Apple 高刷、Mac 输入/切换、高级 Pencil 与协议样例均已包含。正式分发身份和批准的最终品牌素材仍是外部前提；实机性能单独验收。

## 源码自动关卡

执行完整[开发检查](development.zh-CN.md)：生产代码 TLS/Keychain/Keystore 实例、认证拒绝、共用协议样例、资源归属/取消、全平台构建、Android Lint、网站/文档/发行检查、打包测试和品牌导出检查。模拟器结果与实机性能分开记录；托管 Actions 不可用不能报告为通过。

## 实机矩阵

- Mac：双向发送/接收，镜像/扩展与全部桌面模式，Wi-Fi/以太网/直连切换，睡眠唤醒/热插拔，Intel/Apple silicon，焦点输入与紧急释放。
- Apple 接收端：硬件 HEVC/H.264 回退，目标与实际刷新率，Pencil 压感/倾斜/旋转/橡皮擦/双击/挤压及绘画软件快捷映射。
- Android：配对 LAN 和 ADB USB，厂商解码/回退与吞吐限制，分配/GC 测量，双接收端并发及独立 forward。
- 传输：同分辨率/编码/码率/温度的 USB/Wi-Fi 对比，30 分钟和两小时运行，温度、内存、重连与资源残留证据。
- UI/品牌：真实 launcher/Dock，浅色/深色和小尺寸，键盘导航及移动端旋转/Dynamic Type。

早期 Preview 2 证据涵盖一台 OnePlus 的 USB HEVC/120 与 H.264/60、触摸/滚动、拔线/ADB/授权恢复，以及一个 iPhone/Android 并发。一次 Wi-Fi 报告在目标 120fps 下约为 109–111fps；这不证明持续 120fps、新 TLS 性能、全部硬件或双 Android。

只有具备设备/OS、源码提交、准确配置、时长、实际渲染指标、故障/恢复结果及一致双语证据，才能改为实机验证通过。没有独立在线显示器时禁止创建虚拟显示器，应记录 SKIP 并继续非交互检查。

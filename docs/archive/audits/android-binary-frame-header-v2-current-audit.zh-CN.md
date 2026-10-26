[English](android-binary-frame-header-v2-current-audit.md) | [简体中文](android-binary-frame-header-v2-current-audit.zh-CN.md)

> 历史记录：保留撰写时的版本、命令和结论，不作为当前操作指南。当前入口见[文档导航](../../README.zh-CN.md)。

# Binary Frame Header V2 与 Legacy 当前审计

当前源码状态：p8 之后已实现 Transport 缓冲池，详见[所有权和分配指南](../../reference/android-binary-frame-header-v2.zh-CN.md)。下文保留此前审计的历史结果。

基线：`79cbf90`；Legacy 真机兼容：**Pending**。

Swift/Java 对 Magic `DWV2`、Version 2、固定 52-byte 大端 Header、Flags、三个正身份字段、非负时间戳，以及包含在 16 MiB 外层绝对上限内的 Payload Length 定义一致。冲突/缺失 Codec Flag、未知 Flag/Version、错误 Header Length、非正身份、截断、长度不符和 Oversize 均拒绝。

Receiver 只在 Core V2 已协商时接受 Binary V2，并校验 Codec Flag 与 Active StreamConfig。Sender 只在 Android 广告完整 Core V2 Capability Set 加独立 `binaryFrameHeaderV2` 时启用。Legacy iOS、部分能力、未知/Core-only V2 和缺失 Identity 均保留 JSON Prefix。

测试包含 Legacy 逐字节断言、Malformed Input、零拷贝 Payload View 和能力门控。Protocol-level Compatibility 已验证；旧 iOS/Android Physical Runtime Compatibility 为 Pending。Transport 仍每帧分配外层 Array，本轮未实现或声称 Buffer Pool。

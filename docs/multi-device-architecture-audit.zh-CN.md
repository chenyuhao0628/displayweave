# 多设备架构审计

状态：代码审计完成；尚未进行双 Android 实体验证。

| 范围 | 证据 | 状态 |
| --- | --- | --- |
| ADB 身份 | 发现与恢复按 Android serial 区分；无线调试端点不会被当作有线设备。 | Architecture Supports |
| 转发端口 | `AndroidAdbForwardManager` 为每个会话分配独立本地端口，并只清理自己持有的映射。 | Code Appears Ready |
| 安装身份 | serial 到 install ID 的状态用于 USB/WiFi 去重，并限制只回退到同一安装实例。 | Code Appears Ready |
| 媒体管线 | 每个 `DeviceSession` 独占 `MacSender`；每个 sender 独占虚拟显示器、SCStream、VTCompressionSession、Transport、统计和输入注入器。 | Architecture Supports |
| 显示/输入身份 | 稳定的每设备 display serial 创建不同虚拟显示器；输入注入使用对应 display ID。 | Code Appears Ready |
| 断开隔离 | 结束单个会话只停止该 sender 和其拥有的 forward；全部断开是独立显式路径。 | Code Appears Ready |
| 统计隔离 | 采集、编码、发送、延迟、队列、benchmark recorder 和自适应控制器均为 sender 实例字段。 | Architecture Supports |
| 实体并发 | 双 Android 独立渲染、触摸映射、恢复和端口清理。 | Needs Physical Verification |

未发现固定转发端口或共享编码器、串流、输入状态。单例 controller 只负责会话集合，不是共享媒体管线。剩余风险来自实体身份变化、并发 ADB 抖动、WindowServer 显示行为和设备特定解码性能。

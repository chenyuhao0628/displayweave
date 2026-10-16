[English](pencil-advanced.md) | [简体中文](pencil-advanced.zh-CN.md)

# Pencil 高级输入

v0.3.0-preview.1 已包含。实际 Pencil 硬件及绘图应用验收仍待完成。

## 行为与边界

在已认证 TLS 会话中，在 `pencil-v1` 基础上协商 `pencil-v2`。整条笔画固定协商模式，旧发送端保持压感/倾角或触摸兼容。V2 增加弧度制旋转及画笔/橡皮工具；Mac 转换为角度制数位笔旋转字段，工具变化时更新接近事件类型。切换工具前取消当前笔画，下一笔使用新工具。不支持旋转数据的设备发送零。

使用 UIKit Pencil 交互回调接收双击与挤压，对 iOS 17.5 功能做可用性检查。挤压只在 ended 阶段触发一次，取消不执行。设置可将每个手势映射为系统偏好、无操作、画笔/橡皮切换、撤销/重做或两个发送端自定义快捷键槽位。不支持的系统偏好不执行远端操作，不会远程运行 iOS 系统快捷指令。

快捷键回传另需默认关闭的发送端许可、辅助功能、已认证 V2 协商和新的操作授权。接收端只发送命名动作，不发送任意键码；两个自定义键码/修饰键组合由发送端配置。每条命令包含当前授权和严格递增的有界序号，每秒最多接受五次。执行前取消触摸/数位笔状态，同步发送完整修饰键/按下/抬起/释放序列。连接、目标和许可变化撤销授权。所有事件在派发前复用接收端已有有界队列准入。

界面区分基础、高级和快捷键授权状态。旋转/工具使用数位笔接口，但不保证所有绘图应用支持；快捷键是用户为当前 Mac 前台应用显式配置的映射。不包含剪贴板、应用自动化、系统快捷指令执行或自动识别绘图应用。

## 验收

严格 V1/V2 解析、无效数字/工具拒绝、整笔模式锁定、旋转换算、橡皮接近事件、中途取消、手势映射、快捷键授权/序号/频率上限、默认值及撤销。CGEvent 捕获测试不得向用户桌面注入输入。双 Apple 构建、生产安全 iOS 运行测试和界面检查使用隔离模拟器。实体 Pencil Pro/双击/悬停和绘图应用矩阵单独记录。

## API 依据

2026-10-16 核对 Apple 文档及本机 Xcode SDK 头文件：

- [UIPencilInteraction](https://developer.apple.com/documentation/uikit/uipencilinteraction) 及 [delegate](https://developer.apple.com/documentation/uikit/uipencilinteractiondelegate)。
- [UITouch rollAngle](https://developer.apple.com/documentation/uikit/uitouch/rollangle)：iOS 17.5 起可用，不支持的设备返回零。UIKit 头文件注明弧度单位和相对于唤醒时的参考角。
- [CGEvent tabletEventRotation](https://developer.apple.com/documentation/coregraphics/cgeventfield/tableteventrotation)。SDK 的 `IOLLEvent.h` 定义旋转能力位 `0x2000` 和橡皮指针类型 `3`。

## 启用与配置

TLS 配对后，打开 iPad 设置 → Apple Pencil。可直接选工具，或配置双击/挤压动作。跟随系统仅映射系统画笔/橡皮切换；调色板、墨水属性、上个工具及系统快捷指令不执行远端动作，界面有相应说明。iPadOS 17.5+ 从触摸及悬停读取旋转并归一化到一周，不支持的硬件保持零。打开设置面板或应用处于非活动状态时不转发手势动作。

需要键盘动作时，在 Mac“设置 → 权限与诊断”启用**允许 Pencil 手势执行快捷键**并授予辅助功能权限。撤销为 Command-Z，重做为 Shift-Command-Z；自定义槽位 1/2 可选择 Mac 物理键和 Shift/Control/Option/Command，默认分别为 E 和 B。这些动作使用当前前台应用快捷键，不是通用绘图工具。保存发送端许可，不保存授权或持有输入。每次动作检查许可/权限，空闲变化最多两秒内检查。系统撤权可能阻止释放事件送达，但持有输入状态仍会清空。

## 自动化证据

严格 V1/V2 和事件捕获测试覆盖旋转换算、橡皮接近事件、工具变化、非法字段（含 JSON 布尔值）、旧版整笔兼容、手势去重、权限丢失、完整快捷键释放、非法自定义偏好、一秒频率上限和旧授权拒绝。生产 iOS 接收器通过真实双向 TLS 发送 V2 旋转/橡皮/取消及已授权快捷键，再降级至 V1 且不发送快捷键；仍覆盖实时撤销配对与退后台关闭监听。隔离 iPhone 模拟器检查了设置区域的浅色/深色未连接状态。这不等同于实体 Pencil 回调或绘图应用验证。

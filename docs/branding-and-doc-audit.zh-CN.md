[English](branding-and-doc-audit.md) | [简体中文](branding-and-doc-audit.zh-CN.md)

# DisplayWeave 品牌与文档审计

Preview 2 网站采用深墨蓝、青色信号路径、非对称首屏、代码原生连接拓扑、发布轨道和证据状态板，不再沿用 OpenDisplay 式白底居中产品页。OpenDisplay 来源、GPL-3.0 与 SideScreen 技术参考继续保留。后续台前调度身份修复仅迁移 macOS 正式版与 Debug Bundle ID，并提供旧偏好迁移；iOS/Android 标识和 `_opensidecar._tcp` 继续作为兼容契约保留。

| 检查点 | 实装结果 |
| --- | --- |
| 色彩 | 深墨蓝背景；青/蓝/绿/琥珀状态 token |
| 首屏 | 文案与 Mac/Android/Apple USB/WiFi 拓扑非对称排列 |
| 容器 | 开放 band；只对下载和状态使用有意义边界 |
| 字体 | Sans 内容、Mono 版本/状态/指标 |
| Release | 三平台签名边界、精确文件名、SHA256SUMS 前置 |
| 响应式 | 390px 纵向拓扑、单列下载轨道、语言入口保留 |
| 动效 | 克制路径脉冲，完整 reduced-motion 回退 |

用户选择不生成/展示图像概念，因此批准的文字规格是视觉基准；英文/中文桌面 1440×1000 与移动 390×844 浏览器截图用于核对。Grid 最小内容宽度造成的移动裁切在验收中被发现并修复。

现行用户文档采用英文主文件与 `.zh-CN.md` 中文配对。历史计划可保留原语言，但必须明确为内部记录。

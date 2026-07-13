[English](brand-assets.md) | [简体中文](brand-assets.zh-CN.md)

# DisplayWeave 品牌资源

当前 Preview 使用 `public/logo.png` 作为完整品牌资源，`public/icon.png` 与 `icon-256.png` 作为小尺寸临时标记，`public/og.png` 作为社交预览；原生 Mac、iOS 与 Android 图标使用同一临时 DisplayWeave 衍生标记。

这些资源已移除当前页面的 OpenDisplay 快乐屏幕标识，但仍不是最终生产母版：缺少可追溯透明 master、浅色/深色变体、Android adaptive 前景/背景及全面小尺寸光学检查。网站 Preview 2 使用代码原生 Signal Weave Console 视觉，不复制上游页面结构。

最终导出需检查 Dock、桌面、启动器、设置、通知、README、favicon 与 1200×630 社交卡，并在品牌独立性与法律来源署名之间保持清晰边界。

macOS 正式版与 Debug Bundle ID 已迁移为 `app.displayweave.mac` 和 `app.displayweave.mac.debug`。应用会在启动时迁移旧偏好并显式加载包内 AppIcon；Xcode target、iOS/Android 标识与 `_opensidecar._tcp` 保持不变，因此现有 OpenDisplay iOS Receiver 连接协议不受影响。身份迁移后 macOS 权限需要重新授予。

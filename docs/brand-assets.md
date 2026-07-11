# DisplayWeave Brand Assets

审计日期：2026-07-11

## 结论

仓库已经包含一套可识别的 DisplayWeave 蓝绿设备编织标志，并已替换高可见度的 OpenDisplay 视觉资源。Preview 0.1 可以继续使用这些明确标记的临时衍生资源；但仓库没有透明背景 master、深色背景版本或可编辑矢量源，因此不能把当前集合描述为最终生产品牌包。本轮不自行生成新的最终 logo。

## 当前资源

| 用途 | 路径 | 状态 |
| --- | --- | --- |
| README / 网站完整 logo | `public/logo.png` | DisplayWeave wordmark，1254×1254，无 alpha |
| 网站主图标 | `public/icon.png` | mark-only，1024×1024，无 alpha |
| favicon / 小图标 | `public/icon-256.png` | mark-only，256×256，无 alpha |
| Open Graph / Twitter Card | `public/og.png` | DisplayWeave，1200×630，无 alpha |
| Mac App icon | `Mac/Assets.xcassets/AppIcon.appiconset/*` | 16–1024 多尺寸；1024 master 与 `public/icon.png` 相同 |
| iOS/iPadOS App icon | `iOS/Assets.xcassets/AppIcon.appiconset/*` | 已生成所需尺寸；1024 master 与 `public/icon.png` 相同 |
| iOS App 内 logo | `iOS/Assets.xcassets/AppLogo.imageset/applogo.png` | DisplayWeave 衍生资源 |
| Android launcher icons | `AndroidReceiver/app/src/main/res/mipmap-*/ic_launcher.png` | mdpi–xxxhdpi DisplayWeave mark |
| Android App 内 logo | `AndroidReceiver/app/src/main/res/drawable/app_logo.png` | 512×512 mark-only，无 alpha |

目视检查确认当前完整 logo、OG 卡、Android logo 与 Mac icon 均使用 DisplayWeave 蓝绿设备编织图形，没有继续显示旧 OpenDisplay happy-screen 主品牌。

## 一致性

- Mac 与 iOS 的 1024 图标 SHA-256 相同，均与 `public/icon.png` 相同。
- 网站 favicon 引用 `public/icon-256.png`。
- Open Graph 与 Twitter Card 均引用 `public/og.png`，尺寸为 1200×630。
- README 使用 `public/logo.png`；网站文字品牌统一为 DisplayWeave。
- 原有 `OpenSidecar` / `OpenDisplay` 名称仍存在于 target、bundle ID、协议 service type 和兼容类名中；这些是兼容标识，不是用户可见主品牌。

## Preview 0.1 缺失项

以下项目没有合格源文件，必须在正式品牌定稿时补充：

1. 透明背景的高分辨率 PNG master；
2. SVG/PDF 等可编辑矢量 master；
3. 深色背景专用 logo 与反白版本；
4. macOS/iOS/Android 各平台安全区和小尺寸光学校正记录；
5. Android adaptive icon 的 foreground/background XML 资源；
6. 经许可并覆盖 Mac、iPhone/iPad、Android WiFi/USB 的正式网站截图；
7. 品牌色、最小尺寸、留白和禁止用法规范。

当前 PNG 均无 alpha；这不满足“保持透明背景版本”的最终品牌要求。Preview 0.1 发布清单必须把透明 master 和深色适配标为待补，而不是伪称完成。

## 使用规则

- Preview 0.1 继续使用当前 DisplayWeave 临时资源，不回退到 OpenDisplay logo。
- 不从现有有损/白底 PNG 自动抠图并宣称为最终透明 master。
- 不用 AI 生成或重新诠释最终品牌图，除非维护者明确提供或批准新 master。
- 新资源到位后，统一从同一个 master 导出网站、OG、Mac、iOS 和 Android 尺寸，并在浅色/深色背景及真实 launcher 尺寸检查。

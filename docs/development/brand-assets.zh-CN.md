[English](brand-assets.md) | [简体中文](brand-assets.zh-CN.md)

# DisplayWeave 品牌资源

更新于 2026-11-09。源码已具备可复现导出、Mac 传统圆角方形底板和 Android 自适应包装，保留现有蓝绿设备图形。当前不透明位图仍是临时衍生资源，**不是最终可编辑或透明 master**。本地 p8 产物早于本轮导出流程；v0.3.0 预览已包含可复现导出。

## 来源与输出

| 资源 | 来源 / 规则 |
| --- | --- |
| 图形 | `public/icon.png`，1024×1024 RGB；SHA-256 记录于 `tools/brand-assets.json` |
| 完整字标 | `public/logo.png`，1254×1254 不透明；原样保留 |
| 社交卡片 | `public/og.png`，1200×630 不透明；原样保留 |
| Mac 图标 | 按 `Mac/Assets.xcassets/AppIcon.appiconset/Contents.json` 生成 16–1024 px RGBA 传统图标，外围留白透明 |
| iOS 图标 | 按 `iOS/Assets.xcassets/AppIcon.appiconset/Contents.json`，包含 1024 px marketing 图 |
| 应用内图形 | iOS `AppLogo` 与 Android `drawable/app_logo.png`，512 px |
| 网页小图标 | `public/icon-256.png`，256 px |
| Android 传统图标 | `mipmap-mdpi` 至 `mipmap-xxxhdpi`，48/72/96/144/192 px |
| Android 自适应 | `mipmap-anydpi-v26/ic_launcher.xml`，白色背景及 432 px RGBA 前景画布 |

iOS 的 1024px 输出仍直接复制源文件，字节一致。其余固定使用 Pillow 12.3.0、Lanczos 缩放和显式 PNG 压缩。不同 zlib 构建的 PNG 压缩字节可能不同，验证比较尺寸、色彩模式和解码像素。应用内和传统图标均从同源重新生成；完整字标与社交卡片不从图形重新拼制。

Mac 应用图标是平台专用衍生图，不替换 master：完整不透明原图缩放至 1024px 画布中的 824px 白色底板，外围留白 100px，轮廓为五阶超椭圆。彩色图形保持在完全不透明的区域内。小尺寸 Mac 图标的颜色使用 Lanczos、alpha 使用面积采样，避免极浅边缘像素占用 16/32px 的外围留白。保留从当前 app bundle 加载 `.icns` 的保护逻辑。此传统 ICNS 处理不同于现代 [Icon Composer 图层](https://developer.apple.com/design/human-interface-guidelines/app-icons)，后者应保持未遮罩状态；iOS、Android 和网页输出像素不变。

```bash
python3 -m venv build/brand-venv
build/brand-venv/bin/pip install -r tools/brand-requirements.txt
build/brand-venv/bin/python tools/export-brand-assets.py --check
# 审阅预期修改后：
build/brand-venv/bin/python tools/export-brand-assets.py --write --preview build/brand-masks.png
```

`--check` 检测缺失输出或解码像素变化（XML 按字节比较），校验 Mac RGBA 模式、透明四角、不透明中心、内缩边界和全尺寸彩色图形边界，以及 Android manifest 的图标选择和彩色图形安全区。源文件哈希改变时拒绝导出；替换 master 必须明确审阅并更新规范哈希。流程不抠出 logo 背景、不生成新品牌图案。现有 `--preview` 联系表用于 Android adaptive 遮罩；Mac 验收检查打包 app 在 Dock 和 Command-Tab 切换器中的显示。

## 安全区、色彩与用法

Android adaptive layer 使用 108dp 画布，当前不透明图标居中放置为 76dp，背景同为白色。全部彩色像素位于中央直径 66dp 的安全圆内。只有 inset 位图外围透明，**不是抠出的透明 logo**。XML 供 API 26+ 使用，保留各密度 PNG；不虚构 monochrome/themed mask，此项需要独立批准的 master。

工作色板：深蓝 `#103A60`、青绿 `#00A5AF`、青蓝 `#00A9DE`、白色 `#FFFFFF`。这些用于配套界面，不用于精确替换原图渐变。状态色遵循 [UI 规范](ui-guidelines.zh-CN.md)，必须配文字。

应用图标使用无字标图形。留白至少一个线宽；不裁切、拉伸、改色、加阴影，不将当前不透明位图当成透明素材。Mac 衍生图只改变外围底板和留白；共用 master 与其他平台背景仍保持不透明且原样不变。深色界面在批准深色 master 前使用明确的白色底板和足够对比，不称其为深色 logo。普通内容建议至少 32px；平台要求的 Mac 16px 图标只是回退资源，不代表已完成小尺寸光学校正。完整字标保持可读，不缩成 favicon。

## 证据与外部条件

导出器复现 36 个资源，验证 Mac 透明度/留白与 Android 安全区。旧的不透明 Mac 资源无法通过新检查，重新生成的七种 Mac 尺寸均通过。共用 master 和全部 29 个非 Mac 输出已验证字节一致。由真实 Mac target 构建的 arm64/x86_64 签名预览 app 在打包 `.icns` 中保留 RGBA 底板，已在真实 Dock 和 Command-Tab 切换器中观察到圆角图标。较早的 Android assemble/Lint 和 Apple 包装记录保留各自原有范围；本次检查不代表旧版 macOS 或 OEM launcher 验收。

Mac 专用圆角轮廓与留白已由提出请求的所有者于 2026-11-09 接受；此决定不替换共用原图，也不代表批准了新的 master。

仍等待外部条件：批准的可编辑 SVG/PDF、透明高分辨率 master、深色/反白及 monochrome master、最终小尺寸光学校正、授权实机宣传截图。未找到原始 `newicon.svg` / `newnewicon.png`。不得虚构批准或替换当前身份。素材到位后统一导出各平台，再检查真实 launcher、Dock、设置、引导页和通知界面。兼容 bundle ID、target 名称和发现身份保持不变。

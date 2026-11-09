[English](release-checklist.md) | [简体中文](release-checklist.zh-CN.md)

# 正式版发布检查清单

当前版本：**v0.3.4 / 构建 23**。[发布说明](v0.3.4.zh-CN.md)、[准确文件与哈希](current.zh-CN.md)、[本地命令](local-release.zh-CN.md)。

## 发行记录

- [x] 维护者已授权本地签名与发布。工作从干净 `main` 开始；`displayweave/main` 从 `bfbe62e` 快进到 `3d5a97c`，包含已合并的 PR #25、#27、#28 和 #29。PR #29 的四项 CI 均通过。
- [x] `origin/main` 已刷新到 `0f44853`。上游产品树与共同祖先相比有 417 个路径变更；整体整合延期，待单独兼容性审核。
- [x] Mac ZIP/DMG 使用固定 Apple Development 身份签名；与准确下载的 v0.3.3 应用通过 designated requirement 连续性比较。已验证 universal arm64/x86_64 和加固运行时。未公证。
- [x] iOS 设备 IPA 为无签名 arm64，包身份不变。Android Release 自测通过，APK 证书 SHA-256 与项目固定指纹一致。
- [x] 已生成 Sparkle EdDSA 更新源和 Android 更新元数据；六项产物／更新源哈希以及归档、签名、身份检查通过。
- [x] 完整本地门禁通过：65 组 Swift 套件及生产方法夹具、Mac universal Debug 与 iOS Simulator、Android `test assembleDebug lintDebug`、Apple 分发/签名/目录清理/文档/打包回归、36 项品牌导出、网站构建、双语文档、发行链接和 diff 检查。
- [x] Apple↔Java 双向 TLS、Mac/iOS Keychain、安全 iOS runtime 与安全 Android runtime 通过。修复旧服务器回调和服务启停顺序后，Android runtime 连续验证三轮连接模式替换和后台监听关闭，确定性夹具检查旧回调及 20 次立即启停；扩展合成视频、指标与触控检查通过。
在线发行回执、托管 CI 结果、合并祖先关系与实际 Pages 验证见[发行 PR #30](https://github.com/chenyuhao0628/displayweave/pull/30)。PR 分别记录本地与在线证据，并区分维护者自审与独立审批。

Android 签名证书 SHA-256：`89805f045800ea18b56b84b32e8e31b1710a3c7bf3c85fda54d260d1fc6d589d`。高刷行为仍属实验性，不宣称实体性能。对应 Release 公开前，不将发行二进制标记为可下载。

上一版记录见 [v0.3.3](v0.3.3.zh-CN.md)、[v0.3.2](v0.3.2.zh-CN.md) 和[早期检查清单](../archive/releases/release-checklist-through-v0.3.1.zh-CN.md)。

## 后续每次发行

1. 确认授权、干净源码、`displayweave` 远端和新的纯数字正式版本／递增构建号。不发布 preview、beta、RC 或 prerelease。
2. 完成[开发门禁](../development/workflow.zh-CN.md)，审核源码／兼容／签名变化，明确记录无法完成的实机检查。
3. 使用 `tools/package-release.sh`、固定身份及上一份实际公开 Mac 应用作为比较基线，签名材料保持外置。
4. 生成两份更新源，独立核验签名／版本／身份／大小／哈希，原样写入 `public/`。同步更新当前指南、网站与发行检查。
5. 提交并标记与产物匹配的源码，归档跟踪源码、许可证和构建脚本。最终清单包含四个二进制包、两个更新源和源码；加清单共 8 个文件。
6. 以未发布 GitHub 草稿暂存，核验全部附件后直接发布正式版。禁止覆盖公开文件或 tag。下载只使用 GitHub Releases，更新元数据只使用项目 Pages。
7. 合并前要求完整 CI，保留 tag 祖先关系；验证匿名下载和实际在线更新源，再记录结果。确认新正式版可用后，本地仅保留新版本完整安装包。

# DisplayWeave 引导式 macOS DMG 设计

日期：2026-07-14

## 目标

在不改变现有 Sparkle 更新包的前提下，为首次手动安装增加
`DisplayWeave-macOS.dmg`。用户打开 DMG 后应立即看到把
`DisplayWeave.app` 拖入 `Applications` 的安装提示，以及首次运行时如何对
未公证的 ad-hoc 应用进行单次放行、如何授予运行所需系统权限的说明。

## 现状与约束

- Release 当前只发布 `DisplayWeave-macOS.zip`；Sparkle appcast 引用该 ZIP。
- macOS Release 使用 ad-hoc 签名并启用 Hardened Runtime，但没有 Developer ID
  签名和 Apple 公证。
- 因此 DMG 只能改善安装引导，不能消除 Gatekeeper 警告。
- 不指导用户运行 `spctl --master-disable`，也不要求全局开启“任何来源”。用户只
  对 DisplayWeave 单次放行。
- DMG 构建只使用 macOS 自带工具，不引入 Homebrew、npm 或第三方 DMG 生成器。

## 产物策略

每次更新 Release 同时发布：

- `DisplayWeave-macOS.zip`：保持现有内容和文件名，继续作为 Sparkle 更新包。
- `DisplayWeave-macOS.dmg`：供用户首次手动安装。

`SHA256SUMS.txt` 同时覆盖 ZIP 和 DMG。appcast 仍只引用 ZIP，避免改变已经部署的
自动更新协议和签名流程。

不新增 PKG。DisplayWeave 是单一应用包，不需要安装守护进程、系统扩展或写入额外
系统目录；PKG 会引入不必要的管理员授权、卸载和维护成本，也不符合“拖入应用程序”
的交互要求。

## DMG 用户体验

卷标使用 `DisplayWeave Installer`。打开 DMG 后，Finder 窗口包含：

- 左侧 `DisplayWeave.app`。
- 右侧指向 `/Applications` 的 `Applications` 快捷方式。
- 可见的拖动箭头和“将 DisplayWeave 拖入应用程序 / Drag DisplayWeave to
  Applications”背景提示。
- `安装与首次运行说明.rtf`，包含中文优先、英文随后的一份双语说明。

背景同时显示简短的首次运行提示：安装完成后从“应用程序”启动；若 macOS 拦截，
前往“系统设置 → 隐私与安全性”选择“仍要打开”。详细说明文件补充以下内容：

1. 先把应用拖入“应用程序”，不要直接从 DMG 中长期运行。
2. 首次打开可尝试按住 Control 点按应用并选择“打开”；若仍被拦截，使用“隐私与
   安全性 → 仍要打开”。
3. 不需要全局开启“任何来源”。
4. 按应用提示授予屏幕录制、辅助功能和本地网络权限；修改屏幕录制或辅助功能权限
   后重新启动 DisplayWeave。
5. 说明该预览包是 ad-hoc 签名且未公证，并提示用户从官方 GitHub Release 下载、
   对照 `SHA256SUMS.txt` 验证文件。

DMG 不自动弹出脚本或自动打开说明文件。macOS 不提供可信的 DMG autorun 机制；所有
提示通过 Finder 背景和清晰命名的说明文件呈现。

## 构建结构

新增独立脚本 `tools/create-guided-dmg.sh`，接口为：

```text
create-guided-dmg.sh <DisplayWeave.app> <output.dmg>
```

脚本职责保持单一：

1. 校验输入是结构完整且签名验证通过的 `DisplayWeave.app`。
2. 创建临时工作目录，复制 App、建立 `/Applications` 符号链接并生成双语 RTF。
3. 使用一个小型 Swift/AppKit 辅助脚本生成确定尺寸的双语背景 PNG。
4. 用 `hdiutil` 创建并挂载可写临时镜像，再通过固定版本的 `ds_store` 与
   `mac_alias` 直接写入 Finder 窗口大小、图标位置、图标尺寸和背景图片 Alias。
   这样构建不依赖 Finder 自动化权限，也不受无图形界面 CI 影响。
5. 确认根目录 `.DS_Store` 不仅存在，而且包含 `backgroundImageAlias`；同时确认
   `.background/DisplayWeave.png` 已写入后再卸载镜像。
6. 转换为只读压缩 UDZO DMG，执行结构和镜像校验，再原子移动到目标路径。

所有临时目录和挂载点都由 `trap` 清理。输入缺失、签名失败、Finder Alias 未写入、
卸载失败或最终校验失败时，脚本返回非零，并删除未完成的输出，防止 CI 发布降级产物。

`tools/package-preview-0.1.sh` 在完成 App 签名验证后，先生成原有 ZIP，再调用该脚本
生成 DMG。开发预览脚本暂不增加 DMG，避免扩大本次公开 Release 以外的范围。

## 发布流水线与文档

`.github/workflows/release.yml` 增加 DMG 的校验和计算和 Release 上传，但 Sparkle
`generate_appcast` 的输入与 ZIP 文件名保持不变。

`tools/verify-update-release.sh` 增加以下发布门禁：

- DMG 必须存在且能通过 `hdiutil verify`。
- 只读挂载后必须存在 App、`Applications` 链接、双语说明、背景文件和 `.DS_Store`。
- 镜像内 App 的 bundle identifier 必须为 `app.displayweave.mac`，且递归严格签名
  校验通过。
- `SHA256SUMS.txt` 必须包含 DMG；appcast 仍必须引用 ZIP，且不得误引用 DMG。

README、自动更新说明、发布检查清单和双语发布文档将明确区分：DMG 用于首次安装，
ZIP 用于 Sparkle 更新。已有历史 Release 的固定哈希和产物清单不回写，以免篡改历史
发布记录。

## 验证策略

实现完成后执行：

1. Shell 语法检查和仓库现有文档/Release 链接检查。
2. 使用现有 Release App 或重新构建的 Release App 生成 DMG。
3. `hdiutil verify`，再以只读、`nobrowse` 方式挂载检查目录结构、符号链接、背景和
   `.DS_Store`。
4. 对镜像中的 App 执行 `codesign --verify --deep --strict --verbose=2`，并检查 bundle
   identifier。
5. 运行 `tools/verify-update-release.sh`，确认 DMG、ZIP、appcast 和校验清单的角色
   没有混淆。
6. 手动打开一次 DMG，确认 Finder 布局、中文与英文文本、拖动路径在默认浅色/深色
   外观下均可读。

## 验收标准

- Release 同时提供稳定文件名的 ZIP 和 DMG。
- 用户打开 DMG 即能看懂“拖入应用程序”，无需先阅读外部网页。
- DMG 同时展示首次运行的单次放行入口，并明确不需要全局开启“任何来源”。
- 详细说明覆盖屏幕录制、辅助功能和本地网络权限。
- DMG 内 App 与 ZIP 内 App 来自同一次构建，bundle identifier 和签名验证一致。
- Sparkle 继续使用 ZIP，现有自动更新验证不回归。
- CI 无法生成或验证引导布局时停止发布，而不是上传不完整 DMG。

## 非目标

- 本次不购买或配置 Developer ID 证书，不接入 Apple 公证。
- 本次不创建 PKG、不修改 App 自身首次启动界面，也不改变 macOS 权限申请逻辑。
- 本次不调整 iOS、iPadOS 或 Android 的打包方式。

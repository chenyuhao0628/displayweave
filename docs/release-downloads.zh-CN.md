[English](release-downloads.md) | [简体中文](release-downloads.zh-CN.md)

# 发行下载

发布规则（2026-10-26）：直接发布正式版本，不经过公开 preview、beta 或 RC 候选阶段；GitHub Release 必须设置 `prerelease=false`。可以用未公开草稿暂存文件，校验完成后一次性正式发布，这不构成公开候选版本。历史发行保持不可变。

DisplayWeave 的发行文件以 GitHub Release 附件形式发布在 `chenyuhao0628/displayweave`
上，不存在站外下载主机。

- 路径：`https://github.com/chenyuhao0628/displayweave/releases/download/<tag>/<artifact>`
- Mac 更新产物：`DisplayWeave-macOS.zip`
- Android 更新产物：`DisplayWeave-Android.apk`

已入库的更新源（`public/appcast.xml` 与 `public/android-update.json`）只指向上述
GitHub 发行路径。每次下载都会经由同一条校验链核对大小、SHA-256、包名、版本号、
最低 SDK 与固定签名证书；校验或身份不符时停止更新，而不是切换到其它来源。

仓库规则：不得在文档、发行说明、更新源或应用代码中加入指向站外的压缩包或可执行文件
下载链接。分发统一走 GitHub Releases。

可复现命令与验证要求见[本地发行](local-release.zh-CN.md)。

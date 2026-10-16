[English](local-release.md) | [简体中文](local-release.zh-CN.md)

# 本地构建与发行

维护者授权本地发行时采用此流程，保留现有应用身份与签名密钥。明确记录本地证据，不把不可用的 GitHub 检查标记为成功，不放宽仓库规则。信任与恢复边界见[自动更新](automatic-updates.zh-CN.md)。

## 准备与构建

检查 `git status`、`displayweave` 远端、最高已发行构建号、Xcode/XcodeGen、Android SDK 与 Java、pnpm 及签名材料。使用新的不可变版本／构建号，不覆盖已公开 tag 或产物。最后已发布版本仍为 `0.3.0-preview.2`、构建号 `17`。下方 `0.3.0-preview.3`／`18` 仅为下一次构建示例，不表示已保留或已发行；运行前重新检查 GitHub。

Android keystore 保存在 Git 外的 `~/Library/Application Support/DisplayWeave/Signing/android-preview.jks`；既有 Keychain 服务为 `app.displayweave.android-preview-signing`，account/alias 为 `displayweave-preview`。打包脚本读取密码但不打印。Sparkle 使用 Keychain account `ed25519`。只用现有 Sparkle 的 `generate_keys -p` 检查公钥，必须匹配 `N9dMZV/F1ui58IsEmCv5jFVgDWiWv2yB/01KBlAHFjE=`；不匹配时停止，不生成替代密钥。

先按[权限延续指南](mac-permissions.zh-CN.md)配置现有 Apple 签名身份，并解压上一份已发布 Mac 应用作为比较基线。首次从临时签名迁移时才使用下方迁移开关；以后删除此开关。从仓库根目录运行：

```bash
python3 tools/mac_signing.py xcode-settings
export DISPLAYWEAVE_MAC_BASELINE_APP=/absolute/path/to/previous-release/DisplayWeave.app
export DISPLAYWEAVE_ALLOW_ADHOC_MIGRATION=1
python3 -m venv build/local-release-venv
build/local-release-venv/bin/python -m pip install -r tools/dmg-requirements.txt
export PATH="$PWD/build/local-release-venv/bin:$PATH"
export DISPLAYWEAVE_VERSION_NAME=0.3.0-preview.3
export DISPLAYWEAVE_BUILD_NUMBER=18
export DISPLAYWEAVE_UPDATE_RELEASE=1
export DISPLAYWEAVE_RELEASE_TAG=v0.3.0-preview.3
export DISPLAYWEAVE_OUTPUT_DIR="$PWD/build/release-v0.3.0-preview.3"
test ! -e "$DISPLAYWEAVE_OUTPUT_DIR"
./tools/package-preview-0.1.sh
```

脚本生成 Xcode 项目，构建固定 Apple 签名的 Mac 应用及引导式 DMG／ZIP、无签名 iOS 设备包，并执行 Android 测试及已签名 Release 构建。不要并发运行使用相同 derived-data 目录的打包任务。禁止开启 shell tracing 或把私钥导出到文件。

## 生成并验证更新源

```bash
export DISPLAYWEAVE_RELEASE_BASE_URL=https://github.com/chenyuhao0628/displayweave/releases/download
export DISPLAYWEAVE_PUBLISHED_AT="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
export DISPLAYWEAVE_ANDROID_APK="$DISPLAYWEAVE_OUTPUT_DIR/DisplayWeave-Android.apk"
export DISPLAYWEAVE_ANDROID_FEED_OUTPUT="$DISPLAYWEAVE_OUTPUT_DIR/android-update.json"
./tools/generate-android-update-manifest.sh
```

将新 Mac ZIP 单独复制到空的 appcast 输入目录。使用构建中的 `build/preview-0.1-mac-derived/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_appcast`，参数为 `--account ed25519`、`--versions 18`、`--download-url-prefix https://github.com/chenyuhao0628/displayweave/releases/download/v0.3.0-preview.3/`、`--link https://github.com/chenyuhao0628/displayweave`、`-o "$DISPLAYWEAVE_OUTPUT_DIR/appcast.xml"` 和该目录。工具使用现有 Keychain 密钥签名。

为四个二进制包与两个更新源生成 `SHA256SUMS.txt`，运行 `./tools/verify-update-release.sh "$DISPLAYWEAVE_OUTPUT_DIR"`。另行验证 ZIP 的 Ed25519 签名与内置公钥、Mac `arm64 x86_64` 架构及 bundle/feed 身份、无签名 iOS arm64 版本和身份。APK 证书 SHA-256 必须保持 `89805f045800ea18b56b84b32e8e31b1710a3c7bf3c85fda54d260d1fc6d589d`。

## 本地回归与对应源码

运行全部[开发门禁](development.zh-CN.md)：52 组 Swift、Mac Debug universal 构建、iOS 模拟器构建、Android `test assembleDebug lintDebug`、网站构建、双语文档、发布链接和空白检查。完整日志保存在被忽略的 `build/`。没有独立在线显示器时不运行虚拟显示测试，单独记录真机缺口。

把生成的更新源原样复制到 `public/`，更新当前发布链接／哈希及双语说明，审查并提交。原生源码与打包输入必须匹配二进制，任何一项变化都应重新构建。为验证过的提交打 tag。执行 `git archive --format=tar.gz --prefix=DisplayWeave-v0.3.0-preview.3/ v0.3.0-preview.3 -o "$DISPLAYWEAVE_OUTPUT_DIR/DisplayWeave-v0.3.0-preview.3-source.tar.gz"` 生成对应跟踪源码包，将其哈希加入校验和文件并验证全部七项。即使 GitHub 公开访问失败，源码、GPL-3.0 与构建脚本仍与安装包同时可用。

## 上传与合并

在验证过的 tag 创建 GitHub 草稿 Release，明确上传八个文件：四个二进制包、两个更新源、源码包和校验和文件。禁止 `--clobber`。核对上传大小／摘要，或通过已认证 API 独立下载验证。

下载并核对在线文件哈希，再公开 GitHub Release。审查最终 PR，按维护者授权合并，分别如实记录本地与托管检查结果。使用 merge commit 保留发行 tag 祖先关系，同步本地／远端 main。

GitHub API 上传成功本身不证明匿名下载可用，每次发行都要重新检查 Release 和 Pages feed。2026-10-16 再次检查时 GitHub Pages 已返回 HTTP 200，最新部署成功；早期 404/账户失败只是历史证据。本地 p8（15）与当前公开列表分别记录。Apple 正式分发使用[独立关卡流程](apple-distribution.zh-CN.md)，上述脚本仍为预览打包。

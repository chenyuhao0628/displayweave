[English](local-release.md) | [简体中文](local-release.zh-CN.md)

# 本地构建与发行

维护者授权本地发行、托管 Actions 不可用时采用此流程，保留现有应用身份与签名密钥。明确记录本地证据，不把不可用的 GitHub 检查标记为成功，不放宽仓库规则。信任与恢复边界见[自动更新](automatic-updates.zh-CN.md)。

## 准备与构建

检查 `git status`、`displayweave` 远端、最高已发行构建号、Xcode/XcodeGen、Android SDK 与 Java、pnpm 及签名材料。使用新的不可变版本／构建号，不覆盖已公开 tag 或产物。p8 使用版本 `0.2.1-p8`、构建号 `15`。

Android keystore 保存在 Git 外的 `~/Library/Application Support/DisplayWeave/Signing/android-preview.jks`；既有 Keychain 服务为 `app.displayweave.android-preview-signing`，account/alias 为 `displayweave-preview`。打包脚本读取密码但不打印。Sparkle 使用 Keychain account `ed25519`。只用现有 Sparkle 的 `generate_keys -p` 检查公钥，必须匹配 `N9dMZV/F1ui58IsEmCv5jFVgDWiWv2yB/01KBlAHFjE=`；不匹配时停止，不生成替代密钥。

从仓库根目录运行：

```bash
python3 -m venv build/local-release-venv
build/local-release-venv/bin/python -m pip install -r tools/dmg-requirements.txt
export PATH="$PWD/build/local-release-venv/bin:$PATH"
export DISPLAYWEAVE_VERSION_NAME=0.2.1-p8
export DISPLAYWEAVE_BUILD_NUMBER=15
export DISPLAYWEAVE_UPDATE_RELEASE=1
export DISPLAYWEAVE_RELEASE_TAG=v0.2.1-p8
export DISPLAYWEAVE_OUTPUT_DIR="$PWD/build/release-p8"
./tools/package-preview-0.1.sh
```

脚本生成 Xcode 项目，构建 ad-hoc Mac 应用及引导式 DMG／ZIP、无签名 iOS 设备包，并执行 Android 测试及已签名 Release 构建。不要并发运行使用相同 derived-data 目录的打包任务。禁止开启 shell tracing 或把私钥导出到文件。

## 生成并验证更新源

```bash
export DISPLAYWEAVE_RELEASE_BASE_URL=https://downloads.urlget.cyou/releases
export DISPLAYWEAVE_RELEASE_FALLBACK_BASE_URL=https://github.com/chenyuhao0628/displayweave/releases/download
export DISPLAYWEAVE_PUBLISHED_AT="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
export DISPLAYWEAVE_ANDROID_APK="$DISPLAYWEAVE_OUTPUT_DIR/DisplayWeave-Android.apk"
export DISPLAYWEAVE_ANDROID_FEED_OUTPUT="$DISPLAYWEAVE_OUTPUT_DIR/android-update.json"
./tools/generate-android-update-manifest.sh
```

将新 Mac ZIP 单独复制到空的 appcast 输入目录。使用构建中的 `build/preview-0.1-mac-derived/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_appcast`，参数为 `--account ed25519`、`--versions 15`、`--download-url-prefix https://downloads.urlget.cyou/releases/v0.2.1-p8/`、`--link https://github.com/chenyuhao0628/displayweave`、`-o "$DISPLAYWEAVE_OUTPUT_DIR/appcast.xml"` 和该目录。工具使用现有 Keychain 密钥签名。

为四个二进制包与两个更新源生成 `SHA256SUMS.txt`，运行 `./tools/verify-update-release.sh "$DISPLAYWEAVE_OUTPUT_DIR"`。另行验证 ZIP 的 Ed25519 签名与内置公钥、Mac `arm64 x86_64` 架构及 bundle/feed 身份、无签名 iOS arm64 版本和身份。APK 证书 SHA-256 必须保持 `89805f045800ea18b56b84b32e8e31b1710a3c7bf3c85fda54d260d1fc6d589d`。

## 本地回归与对应源码

运行全部[开发门禁](development.zh-CN.md)：37 组 Swift、Mac Debug universal 构建、iOS 模拟器构建、Android `test assembleDebug`、网站构建、双语文档、发布链接和空白检查。完整日志保存在被忽略的 `build/`。没有独立在线显示器时不运行虚拟显示测试，单独记录真机缺口。

把生成的更新源原样复制到 `public/`，更新当前发布链接／哈希及双语说明，审查并提交。原生源码与打包输入必须匹配二进制，任何一项变化都应重新构建。为验证过的提交打 tag。执行 `git archive --format=tar.gz --prefix=DisplayWeave-v0.2.1-p8/ v0.2.1-p8 -o "$DISPLAYWEAVE_OUTPUT_DIR/DisplayWeave-v0.2.1-p8-source.tar.gz"` 生成对应跟踪源码包，将其哈希加入校验和文件并验证全部七项。即使 GitHub 公开访问失败，源码、GPL-3.0 与构建脚本仍与安装包同时可用。

## 上传与合并

在验证过的 tag 创建 GitHub 草稿 Release，明确上传八个文件：四个二进制包、两个更新源、源码包和校验和文件。禁止 `--clobber`。核对上传大小／摘要，或通过已认证 API 独立下载验证。

向 Cloudflare Pages 项目 `displayweave-downloads` 的生产分支 `main` 部署完整静态快照，保留所有历史发行路径。新八项文件放在 `/releases/v0.2.1-p8/`；本地 `site-dist/` 复制到 `/displayweave/`，作为备用网站与更新源副本。排除 `functions/`、`_worker.js`、凭据、日志和本地构建目录，检查当前 Pages 文件限制。用 `wrangler pages deploy` 指定项目、分支与已验证源码提交。

下载并核对在线文件哈希，检查备用网站引用的资源，再公开 GitHub Release。审查最终 PR，按维护者授权合并，如实记录本地检查和不可用的托管检查。使用 merge commit 保留发行 tag 祖先关系，同步本地／远端 main。

GitHub API 上传成功不等于匿名下载可用。2026-10-16 的观察是 GitHub 公开访问和 Pages 返回 404，而已认证管理接口和 Cloudflare 正常。两端应用仍从原 GitHub Pages 地址读取更新元数据；备用更新源不会重定向已安装客户端。在原地址恢复前需手动安装，本流程不修改内置更新源身份。

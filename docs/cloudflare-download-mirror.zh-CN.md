[English](cloudflare-download-mirror.md) | [简体中文](cloudflare-download-mirror.zh-CN.md)

# Cloudflare 下载镜像

DisplayWeave 发行文件以静态文件镜像到 Cloudflare Pages：

- 项目：`displayweave-downloads`
- 自定义域名：`downloads.urlget.cyou`
- 路径：`/releases/<tag>/<artifact>`
- 源码模板：`cloudflare-downloads/`

Pages 提供不可变发行文件，以及 `/displayweave/` 下的静态备用网站。部署中不得包含 `functions/` 目录，因此下载不消耗 Workers 调用。每次新部署须包含所有需要继续保留的发行 tag；Pages 部署会替换先前的完整静态快照。

Android p6 使用 `downloads.urlget.cyou` 的精确发行路径作为 APK 主地址，对应 GitHub Release 作为备用。回退仅限连接、HTTP 可用性及传输失败；大小、哈希、包名、版本、SDK 或证书验证失败应停止更新，不切换来源。Android p5 只信任 GitHub，必须先手动升级到 p6。

备用网站包含已入库更新源的副本，不改变已安装应用内置的 GitHub Pages 地址。故障期间的操作见[本地发行](local-release.zh-CN.md)。

禁止提交 Wrangler OAuth 凭据或 API token。自动部署应将限定权限的 Cloudflare API token 保存在 GitHub Actions secret 中。

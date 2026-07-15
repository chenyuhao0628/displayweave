[English](https://github.com/chenyuhao0628/displayweave/blob/main/docs/release-notes-v0.2.1-p2.md) | [简体中文](https://github.com/chenyuhao0628/displayweave/blob/main/docs/release-notes-v0.2.1-p2.zh-CN.md)

# DisplayWeave `v0.2.1-p2` 发布说明

DisplayWeave 0.2.1-p2 修复 Android 自动更新的新鲜度问题，并增加可见的下载进度。

## 改动

- Android 更新清单请求禁用 `HttpURLConnection` 缓存、发送明确的 No-cache Header，并为每次请求加入缓存击穿参数，避免新版本发布后仍读取缓存的旧 Feed。
- 点击安装前以及从“允许安装未知应用”设置返回后，都会重新获取最新清单。
- 若已下载 APK 的版本、URL、大小或 SHA-256 不再匹配当前清单，则拒绝安装；同时继续校验包名、Minimum SDK、Version Code 与固定签名证书。
- 合并重复下载和重复安装操作。
- Android APK 下载期间显示横向百分比进度条。
- 自动删除中断的临时文件、无效或已过期 APK，并在应用更新后的下次启动删除已安装 APK；等待用户确认安装的已验证 APK 会保留在应用专属下载目录中。

## 验证

- 六组 Android 独立 Self Test 全部通过。
- Android Clean Test 与 Debug Assemble 通过，共执行 61 个 Gradle Task。
- 测试构建同时完成 Android Release Source Set 编译。
- `git diff --check` 通过。

更新流程已完成自动化代码与构建验证。通过本次新发布 Feed 完成端到端安装，仍属于发布后的真机检查项目。

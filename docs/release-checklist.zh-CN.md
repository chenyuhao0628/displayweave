[English](release-checklist.md) | [简体中文](release-checklist.zh-CN.md)

# DisplayWeave Preview 0.1 发布检查清单

## 身份与边界

- 标签：`v0.1.0-preview.2`，必须标为 prerelease。
- Android 包名 `app.opendisplay.android` 为兼容标识；APK 使用仓库外 Preview keystore 的 v2 签名。
- Android 证书 SHA-256：`89:80:5F:04:58:00:EA:18:B5:6B:84:B3:2E:8E:31:B1:71:0A:3C:7B:F3:C8:5F:DA:54:D2:60:D1:FC:6D:58:9D`。
- macOS 为 ad-hoc 签名且未公证；iOS 是未签名自签输入包。

## 必须产物

- `DisplayWeave-Preview-0.1-macOS.zip`
- `DisplayWeave-Preview-0.1-Android.apk`
- `DisplayWeave-Preview-0.1-iOS-unsigned-resigning-input.ipa`
- `SHA256SUMS.txt`

## 本地门槛

1. 7 个 Swift policy/self-test 与 4 个 Android standalone self-test 全部 PASS。
2. `pnpm build`、`pnpm run check:docs`、`pnpm run check:release` 通过。
3. `./tools/package-preview-0.1.sh` 完成 macOS Release、iOS unsigned input、Android `clean test assembleRelease`。
4. `codesign --verify --deep --strict` 通过；`apksigner verify --verbose --print-certs` 显示 v2 与正确证书；IPA 只含 `Payload/`，无 `._`/`__MACOSX`。
5. `shasum -a 256 -c SHA256SUMS.txt` 与 `git diff --check` 通过。
6. 中英文 1440×1000 与 390×844 页面无裁切，下载 URL 与 Release 资产逐字一致。

## 真机证据

已验证 OnePlus USB HEVC/120、H.264/60、触摸、双指滚动、回前台、强停重开、ADB 重启、拔插、取消/恢复授权、Auto WiFi 回退与 USB 升级；当前 iPhone WiFi 与 Android 并发。双 Android、受控 Benchmark、30 分钟及 2 小时耐久明确未完成。

## 发布后

核对 GitHub Release 是 prerelease、四个资产名称/大小正确，Pages workflow 成功，`/` 与 `/zh.html` 均展示 Preview 2，且未向上游 `origin` 推送。

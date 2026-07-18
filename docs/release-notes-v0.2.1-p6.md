[English](release-notes-v0.2.1-p6.md) | [简体中文](release-notes-v0.2.1-p6.zh-CN.md)

# DisplayWeave `v0.2.1-p6` release notes

DisplayWeave 0.2.1-p6 introduces a dual-source Android update channel for
networks where GitHub release downloads are unavailable.

## Android update delivery

- Uses `downloads.urlget.cyou` on Cloudflare Pages as the primary APK mirror.
- Falls back to the matching GitHub Release APK only after a connection, HTTP
  availability, or transport failure.
- Requires both URLs to use HTTPS and match exact trusted hosts and release
  paths.
- Applies one shared size, SHA-256, package, version, SDK, and pinned signing
  certificate verification path after either download.
- Does not try another mirror after an oversized artifact, final size mismatch,
  hash failure, package mismatch, version mismatch, or certificate failure.

Android p5 does not trust the new Cloudflare hostname. Install p6 manually once
from the website; p6 and later builds can then use Cloudflare with GitHub as the
automatic fallback.

## Distribution

The release continues to provide the guided macOS DMG, Sparkle ZIP, signed
Android APK, unsigned iOS re-signing input, signed update feeds, and
`SHA256SUMS.txt`.

| Asset | SHA-256 |
| --- | --- |
| `DisplayWeave-macOS.zip` | `d1b5bef839322f34d0cd31067aa78776108a6014233677869fb394b3bc12b44a` |
| `DisplayWeave-macOS.dmg` | `441651dcb54304f2ec147ebdc35db7808d92812631496b99e17f41394f31c691` |
| `DisplayWeave-Android.apk` | `123fea1468335f8412b0f8620623c3c9fa681b36ef5e9e3190e3b1ec2c812083` |
| `DisplayWeave-Preview-0.1-iOS-unsigned-resigning-input.ipa` | `7430569bb68db065a056f827b0538eca780a65455dbed3ce0d69e3503c0320a8` |
| `appcast.xml` | `bf1429a9774c2a2661136832902bc4e032a32b0b83108ea3b567ff206dd7df0c` |
| `android-update.json` | `4fc43c7606b40f786d21872ab3dd1243ecd79308237e75cb3aaff1e84acdb377` |

[GitHub Release](https://github.com/chenyuhao0628/displayweave/releases/tag/v0.2.1-p6) · [Cloudflare mirror](https://downloads.urlget.cyou/releases/v0.2.1-p6/SHA256SUMS.txt)

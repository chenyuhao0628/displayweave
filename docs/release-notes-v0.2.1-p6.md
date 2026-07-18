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

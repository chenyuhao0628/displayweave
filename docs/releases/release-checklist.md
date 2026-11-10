[English](release-checklist.md) | [简体中文](release-checklist.zh-CN.md)

# Stable release checklist

Current release: **v0.3.5 / build 24**. [Release notes](v0.3.5.md), [exact files and hashes](current.md), [local commands](local-release.md).

## Release record

- [x] Maintainer authorized local signing and publication. Work started from clean source at `13ecc58` atop `displayweave/main` (`b0189ac`, v0.3.4).
- [x] Refreshed `origin/main` to `0f44853`. The upstream product tree differs by 417 paths from the shared ancestor; wholesale integration remains deferred for compatibility review.
- [x] Mac ZIP/DMG signed with the pinned Apple Development identity; the v0.3.4 (build 23) app passed designated-requirement continuity. Universal arm64/x86_64 and hardened runtime verified. Not notarized.
- [x] iOS device IPA is unsigned arm64 with the existing bundle identity. Android Release self-tests passed and APK certificate SHA-256 matches the pinned project fingerprint.
- [x] Sparkle EdDSA feed and Android update metadata generated; all six package/feed hashes and archive/signature/identity checks passed.
- [x] Full local gate passed: 65 Swift suites and production-method fixtures; universal Mac Debug and iOS Simulator; Android `test assembleDebug lintDebug`; Apple distribution/signing, workspace cleanup, docs and packaging regressions; 36 brand exports; website build, bilingual docs, release links and diff checks.
- [x] Apple↔Java mutual TLS, Mac/iOS Keychain and isolated iOS video-admission runtime (including swapped-orientation streamConfig and Metal generation/reset guards) passed.
- [x] Draft Release asset verification, anonymous online downloads, Pages feed verification and publication PR merge recorded in [GitHub Release v0.3.5](https://github.com/chenyuhao0628/displayweave/releases/tag/v0.3.5) and [PR #31](https://github.com/chenyuhao0628/displayweave/pull/31).

Android signing certificate SHA-256: `89805f045800ea18b56b84b32e8e31b1710a3c7bf3c85fda54d260d1fc6d589d`. High-refresh behavior remains experimental; no physical performance claim is made. Release binaries are not advertised until the matching Release is public.

Previous release records remain in [v0.3.4](v0.3.4.md), [v0.3.3](v0.3.3.md), [v0.3.2](v0.3.2.md), and the [earlier checklist](../archive/releases/release-checklist-through-v0.3.1.md).

## Every subsequent publication

1. Confirm authorization, clean source, `displayweave` remote and a new stable numeric version/monotonic build. No public preview, beta, RC or prerelease.
2. Run the complete [development gate](../development/workflow.md), review source/compatibility/signing changes and record unavailable hardware explicitly.
3. Build through `tools/package-release.sh` with pinned identities and the exact previous published Mac app as baseline. Keep signing material external.
4. Generate the two update feeds, independently validate signatures/versions/identities/sizes/hashes and persist exact feeds in `public/`. Update current guides, site and release-link checks together.
5. Commit/tag matching source; archive tracked source including license/build scripts. The final manifest covers four binaries, two feeds and source; there are eight files including the manifest.
6. Stage as an unpublished GitHub draft, verify every uploaded asset, then publish as stable. Never overwrite public files or tags. Only GitHub Releases hosts downloads; only the project Pages site hosts update metadata.
7. Require full CI before merge, preserve tag ancestry, verify anonymous downloads and exact deployed feeds, then record results. Keep only the newly verified local stable package set after checking the next release is usable.
